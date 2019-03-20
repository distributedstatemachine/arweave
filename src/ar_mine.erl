-module(ar_mine).
-export([start/6, start/7, change_txs/2, stop/1, start_miner/2, schedule_hash/1]).
-export([validate/3, validate_by_hash/2]).
-include("ar.hrl").
-include_lib("eunit/include/eunit.hrl").

%%% A module for managing mining of blocks on the weave,

%% State record for miners
-record(state, {
	parent, % miners parent process (initiator)
	current_block, % current block held by node
	recall_block, % recall block related to current
	txs, % the set of txs to be mined
	timestamp, % the block timestamp used for the mining
	timestamp_refresh_timer, % Reference for timer for updating the timestamp
	data_segment = <<>>, % the data segment generated for mining
	generate_data_segment_duration, % duration in seconds for last generation of the data segment.
	reward_addr, % the nodes reward address
	tags, % the nodes block tags
	diff, % the current network difficulty
	auto_update_diff, % should the diff be kept or updated automatically
	delay = 0, % hashing delay used for testing
	max_miners = ?NUM_MINING_PROCESSES, % max mining process to start (ar.hrl)
	miners = [], % miner worker processes
	nonces % nonce builder to ensure entropy
}).

%% @doc Spawns a new mining process and returns its PID.
start(CurrentB, RecallB, RawTXs, RewardAddr, Tags, Parent) ->
	do_start(CurrentB, RecallB, RawTXs, RewardAddr, Tags, auto_update, Parent).

start(CurrentB, RecallB, RawTXs, RewardAddr, Tags, StaticDiff, Parent) when is_integer(StaticDiff) ->
	do_start(CurrentB, RecallB, RawTXs, RewardAddr, Tags, StaticDiff, Parent).

do_start(CurrentB, RecallB, RawTXs, unclaimed, Tags, Diff, Parent) ->
	do_start(CurrentB, RecallB, RawTXs, <<>>, Tags, Diff, Parent);
do_start(CurrentB, RecallB, RawTXs, RewardAddr, Tags, Diff, Parent) ->
	start_server(
		#state {
			parent = Parent,
			current_block = CurrentB,
			recall_block = RecallB,
			generate_data_segment_duration = 0,
			reward_addr = RewardAddr,
			tags = Tags,
			max_miners = ar_meta_db:get(max_miners),
			nonces = [],
			diff = Diff,
			auto_update_diff = Diff == auto_update
		},
		RawTXs
	).

%% @doc Stop a running mining server.
stop(PID) ->
	PID ! stop.

%% @doc Update the set of TXs that the miner is mining on.
change_txs(PID, NewTXs) ->
	PID ! {new_data, NewTXs}.

%% @doc Generate a new data_segment and update the timestamp. Adjust for the
%% generation duration, so that the timestamp is as fresh as possible when
%% the update finishes.
update_data_segment(S = #state { txs = TXs }) ->
	update_data_segment(S, TXs).

update_data_segment(S, TXs) ->
	StartTimestamp = os:system_time(seconds),
	BlockTimestamp = StartTimestamp + S#state.generate_data_segment_duration,
	BDS = ar_block:generate_block_data_segment(
		S#state.current_block,
		S#state.recall_block,
		TXs,
		S#state.reward_addr,
		BlockTimestamp,
		S#state.tags
	),
	NewDuration = os:system_time(seconds) - StartTimestamp,
	NewS = S#state {
		timestamp = BlockTimestamp,
		txs = TXs,
		data_segment = BDS,
		generate_data_segment_duration = NewDuration
	},
	maybe_update_difficulty(reschedule_timestamp_refresh(NewS)).

reschedule_timestamp_refresh(S = #state{
	timestamp_refresh_timer = Timer,
	generate_data_segment_duration = DurationSeconds
}) ->
	timer:cancel(Timer),
	case ?MINING_TIMESTAMP_REFRESH_INTERVAL - DurationSeconds  of
		TimeoutSeconds when TimeoutSeconds =< 0 ->
			ar:warn(
				"ar_mine: Updating data segment slower (~B seconds) than timestamp refresh interval (~B seconds)",
				[DurationSeconds, ?MINING_TIMESTAMP_REFRESH_INTERVAL]
			),
			self() ! refresh_timestamp,
			S#state{ timestamp_refresh_timer = no_timer };
		TimeoutSeconds ->
			case timer:send_after(TimeoutSeconds * 1000, refresh_timestamp) of
				{ok, Ref} ->
					S#state{ timestamp_refresh_timer = Ref };
				{error, Reason} ->
					ar:err("ar_mine: Reschedule timestamp refresh failed: ~p", [Reason]),
					S
			end
	end.

maybe_update_difficulty(S = #state{ auto_update_diff = false }) ->
	S;
maybe_update_difficulty(S = #state{ current_block = B, timestamp = Timestamp }) ->
	S#state{ diff = next_diff(B, Timestamp) }.

%% @doc Start the main mining server.
start_server(S, TXs) ->
	spawn(fun() ->
		server(start_miners(update_txs(S, TXs)))
	end).

%% @doc The main mining server.
server(
	S = #state {
		parent = Parent,
		miners = Miners
	}
) ->
	receive
		% Stop the mining process and all the workers.
		stop ->
			stop_miners(Miners),
			ok;
		% Update the miner to mine on a new set of data.
		{new_data, TXs} ->
			server(restart_miners(update_txs(S, TXs)));
		%% The block timestamp must be reasonable fresh since it's going to be
		%% validated on the remote nodes when it's propagated to them. Only blocks
		%% with a timestamp close to current time will be accepted in the propagation.
		refresh_timestamp ->
			server(restart_miners(update_data_segment(S)));
		% Handle a potential solution for the mining puzzle.
		% Returns the solution back to the node to verify and ends the process.
		{solution, Hash, Nonces, MinedTXs, MinedDiff, MinedTimestamp} ->
			Parent ! {work_complete, MinedTXs, Hash, MinedDiff, Nonces, MinedTimestamp},
			stop_miners(Miners)
	end.

%% @doc Start the workers and return the new state.
start_miners(S = #state {max_miners = MaxMiners}) ->
	Miners =
		lists:map(
			fun(_) -> spawn(?MODULE, start_miner, [S, self()]) end,
			lists:seq(1, MaxMiners)
		),
	lists:foreach(
		fun(Pid) -> Pid ! hash end,
		Miners
	),
	S#state {miners = Miners}.

%% @doc Stop all workers.
stop_miners(Miners) ->
	lists:foreach(
		fun(Pid) -> Pid ! stop end,
		Miners
	).

%% @doc Stop and then start the workers again and return the new state.
restart_miners(S) ->
	stop_miners(S#state.miners),
	start_miners(S).

%% @doc Takes a state and a set of transactions and return a new state with the
%% new set of transactions.
update_txs(S = #state { diff = auto_update }, TXs) ->
	%% We haven't set the timestamp and difficulty yet because that's done later
	%% in update_data_segment/2. The difficulty is needed for the
	%% ar_tx:verify/3 call, so let's updated the block data segment with emtpy
	%% transactions just to get the difficulty.
	update_txs(update_data_segment(S, []), TXs);
update_txs(
	S = #state {
		current_block = CurrentB,
		diff = Diff
	},
	TXs
) ->
	%% Filter out invalid TXs. A TX can be valid by itself, but still invalid
	%% in the context of the other TXs and the block it would be mined to.
	ValidTXs =
		lists:filter(
			fun(TX) ->
				ar_tx:verify(TX, Diff, CurrentB#block.wallet_list)
			end,
			ar_node_utils:filter_all_out_of_order_txs(
				CurrentB#block.wallet_list,
				TXs
			)
		),
	update_data_segment(S, ValidTXs).

%% @doc A worker process to hash the data segment searching for a solution
%% for the given diff.
%% TODO: Change byte string for nonces to bitstring
start_miner(S, Supervisor) ->
	process_flag(priority, low),
	miner(S, Supervisor).

miner(
	S = #state {
		data_segment = BDS,
		diff = Diff,
		nonces = Nonces,
		txs = TXs,
		timestamp = Timestamp
	},
	Supervisor
) ->
	receive
		stop -> ok;
		hash ->
			schedule_hash(S),
			case validate(BDS, iolist_to_binary(Nonces), Diff) of
				false ->
					case(length(Nonces) > 512) and coinflip() of
						false ->
							miner(
								S#state {
									nonces =
										[bool_to_binary(coinflip()) | Nonces]
								},
								Supervisor
							);
						true ->
							miner(
								S#state {
									nonces = []
								},
								Supervisor
							)
					end;
				Hash ->
					Supervisor ! {solution, Hash, iolist_to_binary(Nonces), TXs, Diff, Timestamp}
			end
	end.

%% @doc Converts a boolean value to a binary of 0 or 1.
bool_to_binary(true) -> <<1>>;
bool_to_binary(false) -> <<0>>.

%% @doc A simple boolean coinflip.
coinflip() ->
	case rand:uniform(2) of
		1 -> true;
		2 -> false
	end.

%% @doc Schedule a hashing attempt.
%% Hashing attempts can be delayed for testing purposes.
schedule_hash(S = #state { delay = 0 }) ->
	self() ! hash,
	S;
schedule_hash(S = #state { delay = Delay }) ->
	Parent = self(),
	spawn(fun() -> receive after ar:scale_time(Delay) -> Parent ! hash end end),
	S.

%% @doc Given a block calculate the difficulty to mine on for the next block.
%% Difficulty is retargeted each ?RETARGET_BlOCKS blocks, specified in ar.hrl
%% This is done in attempt to maintain on average a fixed block time.
next_diff(CurrentB, NextBlockTimestamp) ->
	ar_retarget:maybe_retarget(
		CurrentB#block.height + 1,
		CurrentB#block.diff,
		NextBlockTimestamp,
		CurrentB#block.last_retarget
	).

%% @doc Validate that a given hash/nonce satisfy the difficulty requirement.
validate(BDS, Nonce, Diff) ->
	case NewHash = ar_weave:hash(BDS, Nonce) of
		<< 0:Diff, _/bitstring >> -> NewHash;
		_ -> false
	end.

%% @doc Validate that a given block data segment hash satisfies the difficulty requirement.
validate_by_hash(BDSHash, Diff) ->
	case BDSHash of
		<< 0:Diff, _/bitstring >> ->
			true;
		_ ->
			false
	end.

%%% Tests: ar_mine

%% @doc Test that found nonces abide by the difficulty criteria.
basic_test() ->
	B0 = ar_weave:init(),
	ar_node:start([], B0),
	B1 = ar_weave:add(B0, []),
	B = hd(B1),
	RecallB = hd(B0),
	start(B, RecallB, [], unclaimed, [], self()),
	receive
		{work_complete, MinedTXs, _Hash, Diff, Nonce, Timestamp} ->
			?assertEqual(MinedTXs, []),
			BDS = ar_block:generate_block_data_segment(
				B,
				RecallB,
				[],
				<<>>,
				Timestamp,
				[]
			),
			Res = crypto:hash(
				?MINING_HASH_ALG,
				<< Nonce/binary, BDS/binary >>
			),
			?assertMatch(
				<< 0:Diff, _/bitstring >>,
				Res
			)
	end.

%% @doc Ensure that we can change the transactions while mining is in progress.
change_txs_test() ->
	[B0] = ar_weave:init(),
	B = B0,
	RecallB = B0,
	FirstTXSet = [ar_tx:new()],
	SecondTXSet = FirstTXSet ++ [ar_tx:new(), ar_tx:new()],
	%% Start mining with a high enough difficulty, so that the mining won't
	%% finish before adding more TXs.
	Diff = 14,
	PID = start(B, RecallB, FirstTXSet, unclaimed, [], Diff, self()),
	change_txs(PID, SecondTXSet),
	receive
		{work_complete, MinedTXs, Hash, _, Nonce, Timestamp} ->
			?assertEqual(SecondTXSet, MinedTXs),
			BDS = ar_block:generate_block_data_segment(
				B,
				RecallB,
				SecondTXSet,
				<<>>,
				Timestamp,
				[]
			),
			?assertEqual(
				Hash,
				crypto:hash(
					?MINING_HASH_ALG,
					<< Nonce/binary, BDS/binary >>
				)
			),
			?assertMatch(
				<< 0:Diff, _/bitstring >>,
				Hash
			)
	end.

%% @doc Ensures ar_mine can be started and stopped.
start_stop_test() ->
	B0 = ar_weave:init(),
	ar_node:start([], B0),
	B1 = ar_weave:add(B0, []),
	B = hd(B1),
	RecallB = hd(B0),
	PID = start(B, RecallB, [], unclaimed, [], self()),
	link(PID),
	stop(PID),
	assert_not_alive(PID, 500).

%% @doc Ensures a miner can be started and stopped.
miner_start_stop_test() ->
	S = #state{},
	PID = spawn_link(fun() -> start_miner(S, self()) end),
	stop_miners([PID]),
	assert_not_alive(PID, 500).

assert_not_alive(PID, Timeout) ->
	Do = fun () -> not is_process_alive(PID) end,
	?assert(ar_util:do_until(Do, 50, Timeout)).
