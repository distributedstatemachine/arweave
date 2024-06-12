-module(ar_start_from_block_tests).

-include_lib("arweave/include/ar_config.hrl").
-include_lib("eunit/include/eunit.hrl").


start_from_block_test_() ->
    [
		{timeout, 240, fun test_start_from_block/0}
	].

test_start_from_block() ->
    [B0] = ar_weave:init([], 0), %% Set difficulty to 0 to speed up tests
	ar_test_node:start(B0),
    ar_test_node:start_peer(peer1, B0),
    ar_test_node:start_peer(peer2, B0),
    ar_test_node:connect_to_peer(peer1),
    ar_test_node:connect_to_peer(peer2),
   
    ar_test_node:mine(peer1),
    ar_test_node:wait_until_height(peer1, 1),
    ar_test_node:wait_until_height(peer2, 1),
    ar_test_node:mine(peer2),
    ar_test_node:wait_until_height(peer1, 2),
    ar_test_node:wait_until_height(peer2, 2),
    ar_test_node:mine(peer1),
    ar_test_node:wait_until_height(peer1, 3),
    ar_test_node:wait_until_height(peer2, 3),

    ar_test_node:disconnect_from(peer1),
    ar_test_node:disconnect_from(peer2),

    ar_test_node:mine(peer1),
    ar_test_node:wait_until_height(peer1, 4),

    ar_test_node:mine(peer2),
    ar_test_node:wait_until_height(peer2, 4),
    ar_test_node:mine(peer2),
    ar_test_node:wait_until_height(peer2, 5),
    ar_test_node:mine(peer2),
    ar_test_node:wait_until_height(peer2, 6),

    ar_test_node:connect_to_peer(peer1),
    ar_test_node:connect_to_peer(peer2),

    ar_test_node:wait_until_height(peer1, 6),
    ar_test_node:wait_until_height(peer2, 6),
    ar_test_node:wait_until_height(6),

    MainBI = ar_node:get_blocks(),

    Tip = ar_test_node:remote_call(peer1, ar_node, get_current_block, []),
    ?LOG_ERROR([{tip, ar_util:encode(Tip#block.indep_hash)}]),
    lists:foreach(
        fun({H, _WeaveSize, _TXRoot}) ->
            B = ar_block_cache:get(block_cache, H),
            ?LOG_ERROR([{height, B#block.height}, {hash, ar_util:encode(H)}])
        end,
        MainBI
    ),

    {StartFrom, _, _} = lists:nth(3, MainBI),
    {StartMinus1, _, _} = lists:nth(4, MainBI),

    ?LOG_ERROR([{reward_history, get_reward_history(ar_test_node:peer_ip(peer1), StartFrom)}]),
    ?LOG_ERROR([{reward_history, get_reward_history(ar_test_node:peer_ip(peer1), StartMinus1)}]),

    ?LOG_ERROR([{start_from, ar_util:encode(StartFrom)}]),

    {ok, Config} = ar_test_node:get_config(peer1),
    ok = ar_test_node:set_config(peer1, Config#config{
        start_from_latest_state = false,
        start_from_block = StartFrom }),
    ar_test_node:restart(peer1),

    ?LOG_ERROR([{reward_history, get_reward_history(ar_test_node:peer_ip(peer1), StartFrom)}]),
    ?LOG_ERROR([{reward_history, get_reward_history(ar_test_node:peer_ip(peer1), StartMinus1)}]),

    NewTip = ar_test_node:remote_call(peer1, ar_node, get_current_block, []),
    ?assertEqual(NewTip#block.indep_hash, StartFrom).



get_reward_history(Peer, H) ->
    case ar_http:req(#{
        peer => Peer,
        method => get,
        path => "/reward_history/" ++ binary_to_list(ar_util:encode(H)),
        timeout => 30000
    }) of
        {ok, {{<<"200">>, _}, _, Body, _, _}} ->
            case ar_serialize:binary_to_reward_history(Body) of
                {ok, RewardHistory} ->
                    RewardHistory;
                {error, Error} ->
                    Error
            end;
        Reply ->
            Reply
    end.


%% RewardHistoryA is missing element 528. Address: 2EjUq1ROtP8VXduBbk7afvjY-shHU0g1Q-w162h4d8U
%% 
%% 
%% It's missing the block at height 1442382
%% There was an orphaned block at about that time
%% It looks like it's gap in the reward history