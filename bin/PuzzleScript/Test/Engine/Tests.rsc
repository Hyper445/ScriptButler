module PuzzleScript::Test::Engine::Tests

import util::IDEServices;
import vis::Charts;
import vis::Presentation;
import vis::Layout;
import util::Web;

import PuzzleScript::IDE::IDE;


import PuzzleScript::Report;
import PuzzleScript::Load;
import PuzzleScript::Engine;
import PuzzleScript::Compiler;
import PuzzleScript::Checker;
import PuzzleScript::AST;
import IO;
import util::Eval;
import Type;
import util::Math;
import List;

import util::Benchmark;

// Object randomObject(list[Object] objs){
// 		int rand = arbInt(size(objs));
// 		return objs[rand];
// 	}

void main() {

    loc DemoDir = |project://AutomatedPuzzleScript/src/PuzzleScript/Test/Tutorials|;
    loc ReportDir = |project://AutomatedPuzzleScript/src/PuzzleScript/Results|;

	PSGame game;
	Checker checker;
	Engine engine;
	Level level;

	game = load(|project://AutomatedPuzzleScript/bin/PuzzleScript/Test/Tutorials/heroes_of_sokoban.PS|);
	// game = load(|project://AutomatedPuzzleScript/bin/PuzzleScript/Test/Tutorials/modality.PS|);
	// game = load(|project://AutomatedPuzzleScript/bin/PuzzleScript/Test/Tutorials/coincounter.PS|);
	// game = load(|project://AutomatedPuzzleScript/bin/PuzzleScript/Test/Tutorials/push.PS|);
	// game = load(|project://AutomatedPuzzleScript/bin/PuzzleScript/Test/demo/blockfaker.PS|);
	// game = load(|project://AutomatedPuzzleScript/bin/PuzzleScript/Test/demo/sokoban_basic.PS|);
	checker = check_game(game);
	engine = compile(checker);

    list[list[Rule]] lrule = engine.level_data[engine.converted_levels[2].original].applied_rules;
    for (list[Rule] rule <- lrule) {

        println(rule[0].left);
    }

    return;

    Level save_level = engine.current_level;

    // println("==== Multiple layer object test ====");

    // list[str] sokoban_moves = ["down", "left", "up", "right", "right", "right", "down", "left", "up", "left", "left", "down", "down", "right", "up", "left", "up", "right", "up", "up", "left", "down", "right", "down", "down", "right", "right", "up", "left", "down", "left", "up", "up"];

    // for (int i <- [0..size(sokoban_moves)]) {
        
    //     str move = sokoban_moves[i];
    //     engine = execute_move(engine, checker, move);

    // }

    // println(check_win_conditions(engine));

    // engine.current_level = save_level;

    // showInteractiveContent(generate_report_per_level(checker, ReportDir));

    Coords begin_player_pos = engine.current_level.player[0];
    Coords old_player_pos = <0,0>;
    Coords new_player_pos = <1,1>;

    println("==== Collision test ====");
    list[str] collision_moves = ["left", "up", "left", "up"];
    // list[str] collision_moves = ["up", "left", "down", "down"];
    for (int i <- [0..size(collision_moves)]) {
        
        str move = collision_moves[i];

        engine = execute_move(engine, checker, move);
        print_level(engine, checker);

        if (i == size(collision_moves) - 2) old_player_pos = engine.current_level.player[0];
        if (i == size(collision_moves) - 1) new_player_pos = engine.current_level.player[0];

    }
    print_level(engine, checker);
    println("Player was unable to push block: <old_player_pos == new_player_pos && new_player_pos != begin_player_pos>");
    println("Win conditions satisfied after correct moves: <check_conditions(engine, "win")>");

    engine.current_level = save_level;

    old_player_pos = engine.current_level.player[0];
    engine = execute_move(engine, checker, "right");
    new_player_pos = engine.current_level.player[0];

    println("Player was unable to move into a wall: <old_player_pos == new_player_pos>");

    return;

    engine.current_level = save_level;

    println("\n=== Win test ====");
    list[str] winning_moves = ["up", "up", "up", "up", "left", "left", "left", "left", "down", "down", "right", 
        "up", "left", "up", "right", "right", "right", "right", "up", "right", "down", "down", "right", "right", "right"];

    for (int i <- [0..size(winning_moves)]) {
        
        str move = winning_moves[i];
        engine = execute_move(engine, checker, move);
        print_level(engine, checker);

    }

    println("Win conditions satisfied after correct moves: <check_win_conditions(engine)>");

    engine.current_level = save_level;

    list[str] losing_moves = ["up", "up"];

    for (int i <- [0..size(losing_moves)]) {
        
        str move = losing_moves[i];
        engine = execute_move(engine, checker, move);

    }

    println("Win conditions not satisfied after wrong moves: <!check_win_conditions(engine)>");

    println("\n=== Mutliple rule test ====");

    engine.current_level = save_level;

    old_player_pos = engine.current_level.player[0];
    engine = execute_move(engine, checker, "up");
    new_player_pos = engine.current_level.player[0];

    println("Player is able to move multiple consecutive blocks: <old_player_pos != new_player_pos>");

}