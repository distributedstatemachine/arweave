-module(ar_coordinated_mining_tests).

-include_lib("arweave/include/ar.hrl").
-include_lib("arweave/include/ar_config.hrl").
-include_lib("arweave/include/ar_consensus.hrl").
-include_lib("eunit/include/eunit.hrl").

-import(ar_test_node, [start_coordinated/1, mine/1, wait_until_height/2, http_get_block/2]).

single_node_one_chunk_coordinated_mining_test_() ->
	{timeout, 120, fun test_single_node_one_chunk_coordinated_mining/0}.

test_single_node_one_chunk_coordinated_mining() ->
	[Node, _ExitNode, ValidatorNode] = start_coordinated(1),
	mine(Node),
	BI = wait_until_height(1, ValidatorNode),
	{ok, B} = http_get_block(element(1, hd(BI)), ValidatorNode),
	?assert(byte_size((B#block.poa)#poa.data_path) > 0).

single_node_two_chunk_coordinated_mining_test_() ->
	ar_test_node:test_with_mocked_functions([
			ar_test_node:mock_to_force_invalid_h1()],
		fun test_single_node_two_chunk_coordinated_mining/0, 120).

test_single_node_two_chunk_coordinated_mining() ->
	[Node, _ExitNode, ValidatorNode] = start_coordinated(1),
	mine(Node),
	BI = wait_until_height(1, ValidatorNode),
	{ok, B} = http_get_block(element(1, hd(BI)), ValidatorNode),
	?assert(byte_size((B#block.poa2)#poa.data_path) > 0).

no_exit_node_test_() ->
	{timeout, 120, fun test_no_exit_node/0}.

test_no_exit_node() ->
	%% Assert that when the exit node is down, CM miners don't share their solution with any
	%% other peers.
	[Node, ExitNode, ValidatorNode] = start_coordinated(1),
	ar_test_node:stop(ExitNode),
	mine(Node),
	timer:sleep(5000),
	BI = ar_test_node:get_blocks(ValidatorNode),
	?assertEqual(1, length(BI)).

coordinated_mining_retarget_test_() ->
	{timeout, 120, fun test_coordinated_mining_retarget/0}.

test_coordinated_mining_retarget() ->
	%% Assert that a difficulty retarget is handled correctly.
	[Node1, Node2, _ExitNode, ValidatorNode] = start_coordinated(2),
	lists:foreach(
		fun(Height) ->
			mine_in_parallel([Node1, Node2], ValidatorNode, Height)
		end,
		lists:seq(0, ?RETARGET_BLOCKS)).

three_node_coordinated_mining_concurrency_test_() ->
	{timeout, 120, fun test_three_node_coordinated_mining_concurrency/0}.

test_three_node_coordinated_mining_concurrency() ->
	%% Assert that three nodes mining concurrently don't conflict with each other and that
	%% each of them are able to win a solution.
	[Node1, Node2, Node3, _ExitNode, ValidatorNode] = start_coordinated(3),	
	wait_for_each_node([Node1, Node2, Node3], ValidatorNode, 0, [0, 1, 2]).

wait_for_each_node(Miners, ValidatorNode, CurrentHeight, ExpectedPartitions) ->
	wait_for_each_node(
		Miners, ValidatorNode, CurrentHeight, sets:from_list(ExpectedPartitions), 20).

wait_for_each_node(
		_Miners, _ValidatorNode, _CurrentHeight, _ExpectedPartitions, 0) ->
	?assert(false, "Timed out waiting for all mining nodes to win a solution");
wait_for_each_node(
		Miners, ValidatorNode, CurrentHeight, ExpectedPartitions, RetryCount) ->
	Partition = mine_in_parallel(Miners, ValidatorNode, CurrentHeight),
	Partitions = sets:del_element(Partition, ExpectedPartitions),
	?LOG_ERROR("********** Mined partition: ~p. Remaining: ~p",[Partition, sets:to_list(Partitions)]),
	case sets:is_empty(Partitions) of
		true ->
			ok;
		false ->
			wait_for_each_node(
				Miners, ValidatorNode, CurrentHeight+1, Partitions, RetryCount-1)
	end.
	
mine_in_parallel(Miners, ValidatorNode, CurrentHeight) ->
	ar_util:pmap(fun(Node) -> mine(Node) end, Miners),
	[{Hash, _, _} | _] = wait_until_height(CurrentHeight + 1, ValidatorNode),
	lists:foreach(
		fun(Node) ->
			[{MinerHash, _, _} | _] = wait_until_height(CurrentHeight + 1, Node),
			?assertEqual(Hash, MinerHash)
		end,
		Miners
	),
	{ok, Block} = ar_test_node:http_get_block(Hash, ValidatorNode),
	case Block#block.recall_byte2 of
		undefined -> ?PARTITION_NUMBER(Block#block.recall_byte);
		RecallByte2 -> ?PARTITION_NUMBER(RecallByte2)
	end.

two_node_coordinated_mining_two_chunk_solution_test_() ->
	ar_test_node:test_with_mocked_functions([
			ar_test_node:mock_to_force_invalid_h1()],
		fun test_two_node_coordinated_mining_two_chunk_solution/0, 120).

test_two_node_coordinated_mining_two_chunk_solution() ->
	[Node1, Node2, ExitNode, ValidatorNode] = start_coordinated(2),
	wait_for_each_node([Node1], ValidatorNode, 0, [0,1]).
	% wait_for_each_node([Node2], ValidatorNode, 0, [0,1]).

	% mine(Node1),
	% BI = wait_until_height(1, ValidatorNode),
	% BI = wait_until_height(1, ExitNode),
	% {ok, B} = http_get_block(element(1, hd(BI)), ValidatorNode),
	% ?assertNotEqual(undefined, B#block.recall_byte2),
	% ?assert(byte_size((B#block.poa2)#poa.data_path) > 0),
	% mine(Node2),
	% BI2 = wait_until_height(2, ValidatorNode),
	% BI2 = wait_until_height(2, ExitNode),
	% {ok, B2} = http_get_block(element(1, hd(BI2)), ValidatorNode),
	% ?assertNotEqual(undefined, B2#block.recall_byte2),
	% ?assert(byte_size((B2#block.poa2)#poa.data_path) > 0).
