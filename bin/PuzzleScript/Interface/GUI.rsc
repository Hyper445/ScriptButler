module PuzzleScript::Interface::GUI

import salix::HTML;
import salix::Core;
import salix::App;
import salix::Index;
import salix::ace::Editor;
import salix::Node;

import util::Benchmark;
import util::ShellExec;
import lang::json::IO;

import PuzzleScript::Report;
import PuzzleScript::Load;
import PuzzleScript::Engine;
import PuzzleScript::Compiler;
import PuzzleScript::Checker;
import PuzzleScript::AST;
import PuzzleScript::Verbs;
import PuzzleScript::DynamicAnalyser;
import PuzzleScript::Tutorials::AST;

import String;
import List;
import Type;
import Set;
import IO;

str start_dsl = "tutorial blockfaker {

    verb walk []
    verb push [0]
    verb collide [1]
    verb vanishpink [2]
    verb vanishblue [3]
    verb vanishpurple [4]
    verb vanishorange [5]
    verb vanishgreen [6]

    lesson 1: Push {
        \"First, the player is taught how to push a block\"
        learn to push
    }
    
    lesson 2: Vanish {
        \"By using the push mechanic, the player moves blocks to make other blocks vanish\"
        learn to push
        learn to vanishpurple
        learn to vanishorange
    }
    
    lesson 3: Obstacle {
        \"Here a dead end is introduced. If the player vanishes the purple blocks too early, the level can not be completed\"
        learn to push
        learn to vanishpurple
        fail if vanishpink
    }
    lesson 4: Combinations {
        \"Different techniques should be applied to complete the level\"
        learn to push
        learn to vanishgreen
        learn to vanishorange
    }
    lesson 5: Moveables {
        \"This level uses all the moveable objects\"
        learn to push
        learn to vanishpink
        learn to vanishpurple
        learn to vanishorange
        learn to vanishblue
        learn to vanishgreen
    }        
}";

data CurrentLine = currentline(int column, int row);
data JsonData = alldata(CurrentLine \start, str action, list[str] lines, CurrentLine end, int id);

alias Model = tuple[str input, str title, Engine engine, Checker checker, int index, int begin_index, str code, str dsl, bool analyzed, Dead_Ends de, Win win, str image, tuple[list[str],list[str],list[str]] learning_goals];
alias Dead_Ends = tuple[list[tuple[Engine, list[str]]], real];
alias Win = tuple[Engine engine, list[str] winning_moves, real time];

data Msg 
	= left() 
	| right() 
	| up() 
	| down() 
	| action() 
	| undo() 
	| reload()
	| win()
	| direction(int i)
    | codeChange(map[str,value] delta)
    | dslChange(map[str,value] delta)
    | textUpdated()
    | load_design()
    | analyse()
    | analyse_all()
    | show(Engine engine, int win, int length)
	;

tuple[str, str] coords_to_json(Engine engine, list[Coords] coords, int index) {

    tuple[int width, int height] level_size = engine.level_data[engine.current_level.original].size;

    str json = "[";

    for (Coords coord <- coords) {
        json += "{\"x\":<coord[1]>, \"y\":<coord[0]>},";
    }
    json = json[0..size(json) - 1];
    json += "]";

    return <json, "{\"index\": <index>}">;

}

tuple[str,str,str] pixel_to_json(Engine engine, int index) {

    tuple[int width, int height] level_size = engine.level_data[engine.current_level.original].size;

    str json = "[";

    for (int i <- [0..level_size.height]) {

        for (int j <- [0..level_size.width]) {

            if (!(engine.current_level.objects[<i,j>])? || isEmpty(engine.current_level.objects[<i,j>])) {
                continue;
            }

            list[Object] objects = engine.current_level.objects[<i,j>];

            str name = objects[size(objects) - 1].current_name;
            ObjectData obj = engine.objects[name];

            for (int k <- [0..5]) {
                for (int l <- [0..5]) {

                    json += "{";
                    json += "\"x\": <j * 5 + l>,";
                    json += "\"y\": <i * 5 + k>,";
                    if(isEmpty(obj.sprite)) json += "\"c\": \"<COLORS[toLowerCase(obj.colors[0])]>\"";
                    else {
                        Pixel pix = obj.sprite[k][l];
                        if (COLORS[pix.color]?) json += "\"c\": \"<COLORS[pix.color]>\"";
						else if (pix.pixel != ".") json += "\"c\": \"<pix.color>\"";
                        else json += "\"c\": \"#FFFFFF\"";
                    }
                    json += "},";
                }
            }
        }
    }
    json = json[0..size(json) - 1];
    json += "]";

    return <json, "{\"width\": <level_size.width>, \"height\": <level_size.height>}", "{\"index\": <index>}">;

}

int get_level_index(Engine engine, Level current_level) {

    int index = 0;
    while (engine.converted_levels[index].original != current_level.original) {
        index += 1;
    }
    return index + 1;

}

Model extract_goals(Engine engine, int win, int length, Model model) {

    int level_index = get_level_index(engine, engine.current_level);

    Tutorial tutorial = tutorial_build(model.dsl);
    Lesson lesson = any(Lesson lesson <- tutorial.lessons, lesson.number == level_index) ? lesson : tutorial.lessons[level_index];
    if (!(any(Lesson lesson <- tutorial.lessons, lesson.number == level_index))) {
        println("Lesson <level_index> not found!");
        return model;
    }
    
    // Get travelled coordinates and generate image that shows coordinates
    // 'win' argument determines the color of the path
    list[Coords] coords = engine.applied_data[engine.current_level.original].travelled_coords;
    tuple[str, str, str] json_data = pixel_to_json(engine, model.index + 1);
    exec("./image.sh", workingDir=|project://automatedpuzzlescript/Tutomate/src/PuzzleScript/Interface/|, args = [json_data[0], json_data[1], json_data[2], "1"]);
    tuple[str, str] new_json_data = coords_to_json(engine, coords, model.index + 1);
    exec("./path.sh", workingDir=|project://automatedpuzzlescript/Tutomate/src/PuzzleScript/Interface/|, args = [new_json_data[0], win == 0 ? "0" : "1", new_json_data[1]]);
    model.index += 1;
    model.image = "PuzzleScript/Interface/path<model.index>.png";

    map[int,list[RuleData]] rules = engine.applied_data[engine.current_level.original].actual_applied_rules;

    model.learning_goals = resolve_verbs(engine, rules, tutorial.verbs, lesson.elems, length);

    return model;


}


Model update(Msg msg, Model model){

    bool execute = false;

	if (model.engine.current_level is level){
		switch(msg){
			case direction(int i): {
                execute = true;
				switch(i){
					case 37: model.input = "left";
					case 38: model.input = "up";
					case 39: model.input = "right";
					case 40: model.input = "down";
				}
			}
			case reload(): {
                model.engine.current_level = model.engine.begin_level;
                model.image = "PuzzleScript/Interface/output_image0.png";
            }
            case codeChange(map[str,value] delta): {
                JsonData json_change = parseJSON(#JsonData, asJSON(delta["payload"]));
                model = update_code(model, json_change, 0);
            }
            case dslChange(map[str,value] delta): {
                JsonData json_change = parseJSON(#JsonData, asJSON(delta["payload"]));
                model = update_code(model, json_change, 1);
            }
            case load_design(): {
                model.index += 1;
                model = reload(model.code, model.index);
                tuple[str, str, str] json_data = pixel_to_json(model.engine, model.index);
                exec("./image.sh", workingDir=|project://automatedpuzzlescript/Tutomate/src/PuzzleScript/Interface/|, args = [json_data[0], json_data[1], json_data[2], "0"]);
            }
            case analyse_all(): {

                int i = 0;

                for (Level level <- model.engine.converted_levels) {

                    list[list[Model]] win_models = [];
                    list[Model] losing_models = [];
                    list[list[Model]] all_losing_models = [];

                    Model new_model = model;
                    new_model.engine.current_level = level; 

                    print_level(new_model.engine, new_model.checker);                  

                    int before = cpuTime();
                    tuple[Engine engine, list[str] winning_moves] result = bfs(new_model.engine, ["up","down","left","right"], new_model.checker, "win", 1);
                    real actual_time = (cpuTime() - before) / 1000000.00;
                    
                    tuple[Engine engine, list[str] winning_moves, real time] result_time = <result[0], result[1], actual_time>;
                    
                    new_model.engine.applied_data[model.engine.current_level.original].shortest_path = result.winning_moves;
                    
                    // Save respective engine states
                    new_model.win = result_time;
                    new_model = extract_goals(new_model.win.engine, 0, size(new_model.win.winning_moves), new_model);
                    win_models += [[new_model]];

                    // before = cpuTime();
                    // list[tuple[Engine, list[str]]] results = get_dead_ends(new_model.engine, new_model.checker, result.winning_moves);
                    // actual_time = (cpuTime() - before) / 1000000.00;

                    // new_model.de = <results, actual_time>;

                    // for (tuple[Engine, list[str]] dead_ends <- new_model.de[0]) {
                    //     new_model = extract_goals(dead_ends[0], 0, size(dead_ends[1]), new_model);
                    //     losing_models += [new_model];
                    // }

                    // all_losing_models += [losing_models];

                    println("Saving results");
                    println(typeOf(win_models));

                    save_results(win_models, "win");
                    // save_results(all_losing_models, "fails");


                }


            }
            case analyse(): {

                int before = cpuTime();
                tuple[Engine engine, list[str] winning_moves] result = bfs(model.engine, ["up","down","left","right"], model.checker, "win", 1);
                real actual_time = (cpuTime() - before) / 1000000.00;
                tuple[Engine engine, list[str] winning_moves, real time] result_time = <result[0], result[1], actual_time>;
                
                model.engine.applied_data[model.engine.current_level.original].shortest_path = result.winning_moves;
                
                // Save respective engine states
                model.win = result_time;
                // model.de = get_dead_ends(model.engine, model.checker, result.winning_moves);

                model.analyzed = true;
            }
            case show(Engine engine, int win, int length): {

                model = extract_goals(engine, win, length, model);
            }
			default: return model;
		}
		
        if (execute) {
            model.index += 1;
            model.engine = execute_move(model.engine, model.checker, model.input, 0);
            if (check_conditions(model.engine, "win")) {
                model.engine.index += 1;
                model.engine.current_level = model.engine.converted_levels[model.engine.index];
            }
            tuple[str, str, str] json_data = pixel_to_json(model.engine, model.index);
            exec("./image.sh", workingDir=|project://automatedpuzzlescript/Tutomate/src/PuzzleScript/Interface/|, args = [json_data[0], json_data[1], json_data[2], "1"]);
            execute = false;
            model.image = "PuzzleScript/Interface/output_image<model.index>.png";
        }
	}

    return model;
}

Model update_code(Model model, JsonData jd, int category) {

    str code = category == 0 ? model.code : model.dsl;
    list[str] code_lines = split("\n", code);
    str new_line = "";

    int row = jd.\start.row;
    int begin = jd.\start.column;
    int end = jd.end.column;

    switch(jd.action) {
        case "remove": {
            new_line = code_lines[row][0..begin] + code_lines[row][end..];
        }
        case "insert": {
            new_line = code_lines[row][0..begin] + intercalate("", jd.lines) + code_lines[row][begin..];
        }
    }
    code_lines[jd.\start.row] = new_line;
    str new_code = intercalate("\n", code_lines);
    
    if (category == 0) model.code = new_code;
    else model.dsl = new_code;

    return model;
}

Model reload(str src, int index) {

	PSGame game = load(src);
	Checker checker = check_game(game);
	Engine engine = compile(checker);

	str title = get_prelude(engine.game.prelude, "title", "Unknown");
 
	Model init() = <"none", title, engine, checker, index, index, src, "", false, <[], 0.0>, <engine,[], 0.0>, "PuzzleScript/Interface/output_image<index>.png", <[],[],[]>>;
    return init();

}

void view_panel(Model m){
    div(class("panel"), () {
        h3(style(("font-family": "BubbleGum")), "Buttons");
        button(onClick(direction(37)), "Left");
        button(onClick(direction(39)), "Right");
        button(onClick(direction(38)), "Up");
        button(onClick(direction(40)), "Down");
        button(onClick(reload()), "Restart");
    });
}

// void view_results(Model m) {

//     div(class("panel"), () {
//         h3("Results");
//         AppliedData ad = m.engine.applied_data[m.engine.current_level.original];
//         p("-- Shortest path --");
//         button(onClick(show(m.win.engine, 1, size(m.win.winning_moves))), "<size(m.win.winning_moves)> steps");
//         p("-- Dead ends --");
//         for (int i <- [0..size(m.de[0])]) {
//             button(onClick(show(m.de[i][0], 0, size(m.de[i][1]))), "<i + 1>");
//         }

//         if (m.learning_goals != <[],[],[]>) {

//             p("-- The following verbs have been used --");
//             p("<intercalate(", ", m.learning_goals[2])>");

//             p("-- The following learning goals are realised --");
//             p("<intercalate(", ", m.learning_goals[0])>");

//             p("-- The following learning goals are not realised --");
//             p("<intercalate(", ", m.learning_goals[1])>");

//         }
//     });
// }

void view(Model m) {

    div(class("header"), () {
        h1(style(("text-shadow": "1px 1px 2px black", "font-family": "Pixel", "font-size": "50px")), "PuzzleScript");
    });

    div(class("main"), () {

        div(class("left"), () {
            div(class("left_top"), () {
                h1(style(("text-shadow": "1px 1px 2px black", "padding-left": "1%", "text-align": "center", "font-family": "BubbleGum")), "Editor"); 
                ace("myAce", event=onAceChange(codeChange), code = m.code);
                button(onClick(load_design()), "Reload");
            });
            div(class("left_bottom"), () {
                div(class("tutomate"), () {
                    h1(style(("text-shadow": "1px 1px 2px black", "padding-left": "1%", "text-align": "center", "font-family": "BubbleGum")), "Tutomate");
                    ace("tutomate", event=onAceChange(dslChange), code = m.dsl, width="100%", height="15%");
                    div(class("panel"), () {
                        h3(style(("font-family": "BubbleGum")), "Get insights");
                        button(onClick(analyse()), "Analyse");
                        button(onClick(analyse_all()), "Analyse all");
                    });
                });
            });
        });
        div(class("right"), onKeyDown(direction), () {
            div(style(("width": "40vw", "height": "40vh")), onKeyDown(direction), () {
                int index = 0;
                index = (m.index == m.begin_index) ? m.begin_index : m.index;
                img(style(("width": "40vw", "height": "40vh", "image-rendering": "pixelated")), (src("<m.image>")), () {});
            });
            // div(class("data"), () {
            //     div(class(""), () {view_panel(m);});
            //     if (m.analyzed) view_results(m);
            // });
        });
    });
}

App[Model]() main(loc game_loc) {

	game = load(game_loc);

	checker = check_game(game);
	engine = compile(checker);

	str title = get_prelude(engine.game.prelude, "title", "Unknown");

    tuple[str, str, str] json_data = pixel_to_json(engine, 0);
    exec("./image.sh", workingDir=|project://automatedpuzzlescript/Tutomate/src/PuzzleScript/Interface/|, args = [json_data[0], json_data[1], json_data[2], "1"]);

	Model init() = <"none", title, engine, checker, 0, 0, readFile(game_loc), start_dsl, false, <[],0.0>, <engine,[],0.0>, "PuzzleScript/Interface/output_image0.png", <[],[],[]>>;
    Tutorial tutorial = tutorial_build(start_dsl);
    SalixApp[Model] counterApp(str id = "root") = makeApp(id, init, withIndex("Test", id, view, css = ["PuzzleScript/Interface/style.css"]), update);

    App[Model] counterWebApp()
      = webApp(counterApp(), |project://automatedpuzzlescript/Tutomate/src/|);

    return counterWebApp;

}