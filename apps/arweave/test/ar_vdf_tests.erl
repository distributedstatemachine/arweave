-module(ar_vdf_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("arweave/include/ar_vdf.hrl").

-define(ENCODED_PREV_OUTPUT, <<"f_z7RLug8etm3SrmRf-xPwXEL0ZQ_xHng2A5emRDQBw">>).
-define(RESET_SEED, <<"f_z7RLug8etm3SrmRf-xPwXEL0ZQ_xHng2A5emRDQBw">>).
-define(MAX_THREAD_COUNT, 4).

%-define(TEST_VDF_DIFFICULTY, 15000000 div 25).
-define(TEST_VDF_DIFFICULTY, 10).

%%%===================================================================
%%% utils
%%%===================================================================

break_byte(Buf, Pos)->
	Head = binary:part(Buf, 0, Pos),
	Tail = binary:part(Buf, Pos+1, size(Buf)-Pos-1),
	ChangedByte = binary:at(Buf,Pos) bxor 1,
	<<Head/binary, ChangedByte, Tail/binary>>.

reset_mix(PrevOutput, ResetSeed) ->
	crypto:hash(sha256, << PrevOutput/binary, ResetSeed/binary >>).

%%%===================================================================

vdf_basic_test_() ->
	{timeout, 1000, fun test_vdf_basic_compute_verify_/0}.

% no reset
test_vdf_basic_compute_verify_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),

	ResetSalt = -1,

	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, PrevOutput, ?TEST_VDF_DIFFICULTY),
	BufferHash1 = <<LastStepCheckpoints1/binary, Output1/binary>>,
	{true, BufferHash1} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),

	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),
	BufferHash2 = <<LastStepCheckpoints2/binary, Output2/binary>>,
	{true, BufferHash2} = ar_vdf:verify(StartSalt2, Output1,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),

	BufferHash1_2 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, BufferHash1_2} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),

	% test damage on any byte, arg (aka negative tests)
	ok = test_vdf_basic_compute_verify_break_(StartSalt1, PrevOutput, 1,
		2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2, ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),

	ok.

test_vdf_basic_compute_verify_break_(StartSalt, PrevOutput, StepBetweenHashCount,
		HashCount, BufferHash, ResetSalt, ResetSeed, ThreadCount, IterationCount)->
	test_vdf_basic_compute_verify_break_(StartSalt, PrevOutput, StepBetweenHashCount,
		HashCount, BufferHash, ResetSalt, ResetSeed,
		ThreadCount, IterationCount, size(BufferHash)-1).

test_vdf_basic_compute_verify_break_(_StartSalt, _PrevOutput, _StepBetweenHashCount,
		_HashCount, _BufferHash, _ResetSalt, _ResetSeed, _ThreadCount, _IterationCount, 0)->
	ok;

test_vdf_basic_compute_verify_break_(StartSalt, PrevOutput, StepBetweenHashCount,
		HashCount, BufferHash, ResetSalt, ResetSeed, ThreadCount, IterationCount, BreakPos)->
	BufferHashBroken = break_byte(BufferHash, BreakPos),
	false = ar_vdf:verify(StartSalt, PrevOutput,
		[{StepBetweenHashCount, HashCount, BufferHashBroken}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	test_vdf_basic_compute_verify_break_(StartSalt, PrevOutput, StepBetweenHashCount,
		HashCount, BufferHash, ResetSalt, ResetSeed, ThreadCount, IterationCount, BreakPos-1).

vdf_reset_test_() ->
	{timeout, 1000, fun test_vdf_reset_verify_/0}.

test_vdf_reset_verify_() ->
	ok = test_vdf_reset_0_(),
	ok = test_vdf_reset_1_(),
	ok = test_vdf_reset_mid_checkpoint_(),
	ok.

test_vdf_reset_0_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSalt = StartSalt1,
	
	MixOutput = reset_mix(PrevOutput, ResetSeed),
	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, MixOutput, ?TEST_VDF_DIFFICULTY),
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),
	
	% partial verify should work
	BufferHash1 = <<LastStepCheckpoints1/binary, Output1/binary>>,
	{true, BufferHash1} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2 = <<LastStepCheckpoints2/binary, Output2/binary>>,
	{true, BufferHash2} = ar_vdf:verify(StartSalt2, Output1,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	<< Step1:?VDF_BYTE_SIZE/binary, _/binary >> = LastStepCheckpoints2,
	BufferHash3 = <<LastStepCheckpoints1/binary, Output1/binary, Step1/binary>>,
	{true, BufferHash3} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP+1, BufferHash3}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	
	BufferHash4 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, BufferHash4} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash4}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

test_vdf_reset_1_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSalt = StartSalt2,
	
	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, PrevOutput, ?TEST_VDF_DIFFICULTY),
	MixOutput = reset_mix(Output1, ResetSeed),
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, MixOutput, ?TEST_VDF_DIFFICULTY),
	
	% partial verify should work
	BufferHash1 = <<LastStepCheckpoints1/binary, Output1/binary>>,
	{true, BufferHash1} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2 = <<LastStepCheckpoints2/binary, Output2/binary>>,
	{true, BufferHash2} = ar_vdf:verify(StartSalt2, Output1,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	<< Step1:?VDF_BYTE_SIZE/binary, Step2:?VDF_BYTE_SIZE/binary, _/binary >> = LastStepCheckpoints2,
	BufferHash3 = <<LastStepCheckpoints1/binary, Output1/binary, Step1/binary>>,
	{true, BufferHash3} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP+1, BufferHash3}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash4 = <<LastStepCheckpoints1/binary, Output1/binary, Step1/binary, Step2/binary>>,
	{true, BufferHash4} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP+1+1, BufferHash4}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	
	BufferHash5 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, BufferHash5} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash5}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

test_vdf_reset_mid_checkpoint_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	% means inside 1 iteration
	ResetSaltFlat = 10,
	ResetSalt= StartSalt1+ResetSaltFlat,
	
	Salt1 = << StartSalt1:256 >>,
	{ok, Output1Part1, LastStepCheckpoints1Part1} = ar_mine_randomx:vdf_sha2_nif(Salt1, PrevOutput, ResetSaltFlat-1, 0, ?TEST_VDF_DIFFICULTY),
	MixOutput = reset_mix(Output1Part1, ResetSeed),
	Salt2 = << ResetSalt:256 >>,
	{ok, Output1Part2, LastStepCheckpoints1Part2} = ar_mine_randomx:vdf_sha2_nif(Salt2, MixOutput, ?VDF_CHECKPOINT_COUNT_IN_STEP-ResetSaltFlat-1, 0, ?TEST_VDF_DIFFICULTY),
	Output1 = Output1Part2,
	LastStepCheckpoints1 = <<LastStepCheckpoints1Part1/binary, Output1Part1/binary, LastStepCheckpoints1Part2/binary>>,
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),
	
	% partial verify should work
	BufferHash1 = <<LastStepCheckpoints1/binary, Output1/binary>>,
	{true, BufferHash1} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2 = <<LastStepCheckpoints2/binary, Output2/binary>>,
	{true, BufferHash2} = ar_vdf:verify(StartSalt2, Output1,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	<< Step1:?VDF_BYTE_SIZE/binary, Step2:?VDF_BYTE_SIZE/binary, _/binary >> = LastStepCheckpoints2,
	BufferHash3 = <<LastStepCheckpoints1/binary, Output1/binary, Step1/binary>>,
	{true, BufferHash3} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP+1, BufferHash3}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash4 = <<LastStepCheckpoints1/binary, Output1/binary, Step1/binary, Step2/binary>>,
	{true, BufferHash4} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, ?VDF_CHECKPOINT_COUNT_IN_STEP+1+1, BufferHash4}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	
	BufferHash5 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, BufferHash5} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash5}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

    % partial verify should work
    assert_verify(StartSalt1, ResetSalt, PrevOutput, 1, lists:reverse(Checkpoints1)),
    assert_verify(StartSalt2, ResetSalt, Output1, 1, lists:reverse(Checkpoints2)),

    Hashes3 = lists:sublist(lists:reverse(Checkpoints2), 1, ?VDF_CHECKPOINT_COUNT_IN_STEP + 1),
    assert_verify(StartSalt1, ResetSalt, PrevOutput, 1, lists:reverse(Checkpoints1) ++ Hashes3),

    Hashes4 = lists:reverse(Checkpoints1) ++ lists:reverse(Checkpoints2),
    assert_verify(StartSalt1, ResetSalt, PrevOutput, 1, Hashes4),

test_vdf_skip_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSalt = -1,
	
	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, PrevOutput, ?TEST_VDF_DIFFICULTY),
	BufferHash1 = Output1,
	FullBufferHash1 = <<LastStepCheckpoints1/binary, Output1/binary>>,
	{true, FullBufferHash1} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash1}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),
	BufferHash2 = Output2,
	FullBufferHash2 = <<LastStepCheckpoints2/binary, Output2/binary>>,
	{true, FullBufferHash2} = ar_vdf:verify(StartSalt2, Output1,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	
	BufferHash1_2 = <<Output1/binary, Output2/binary>>,
	FullBufferHash1_2 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, FullBufferHash1_2} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_2}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

test_vdf_skip_reset_0_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSalt = StartSalt1,
	
	MixOutput = reset_mix(PrevOutput, ResetSeed),
	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, MixOutput, ?TEST_VDF_DIFFICULTY),
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),
	
	% partial verify should work
	BufferHash1 = Output1,
	FullBufferHash1 = <<LastStepCheckpoints1/binary, Output1/binary>>,
	{true, FullBufferHash1} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash1}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2 = Output2,
	FullBufferHash2 = <<LastStepCheckpoints2/binary, Output2/binary>>,
	{true, FullBufferHash2} = ar_vdf:verify(StartSalt2, Output1,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	<< Step1:?VDF_BYTE_SIZE/binary, _/binary >> = LastStepCheckpoints2,
	BufferHash3 = Step1,
	FullBufferHash3 = <<LastStepCheckpoints1/binary, Output1/binary, Step1/binary>>,
	{true, FullBufferHash3} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP+1, 1, BufferHash3}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash4 = <<Output1/binary, Output2/binary>>,
	FullBufferHash4 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, FullBufferHash4} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash4}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

test_vdf_skip_reset_1_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSalt = StartSalt2,
	
	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, PrevOutput, ?TEST_VDF_DIFFICULTY),
	MixOutput = reset_mix(Output1, ResetSeed),
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, MixOutput, ?TEST_VDF_DIFFICULTY),
	
	% partial verify should work
	BufferHash1 = Output1,
	FullBufferHash1 = <<LastStepCheckpoints1/binary, Output1/binary>>,
	{true, FullBufferHash1} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash1}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2 = Output2,
	FullBufferHash2 = <<LastStepCheckpoints2/binary, Output2/binary>>,
	{true, FullBufferHash2} = ar_vdf:verify(StartSalt2, Output1,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	<< Step1:?VDF_BYTE_SIZE/binary, Step2:?VDF_BYTE_SIZE/binary, _/binary >> = LastStepCheckpoints2,
	BufferHash3 = Step1,
	FullBufferHash3 = <<LastStepCheckpoints1/binary, Output1/binary, Step1/binary>>,
	{true, FullBufferHash3} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP+1, 1, BufferHash3}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash4 = Step2,
	FullBufferHash4 = <<LastStepCheckpoints1/binary, Output1/binary, Step1/binary, Step2/binary>>,
	{true, FullBufferHash4} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP+1+1, 1, BufferHash4}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash5 = <<Output1/binary, Output2/binary>>,
	FullBufferHash5 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, FullBufferHash5} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash5}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

test_vdf_skip_reset_mid_checkpoint_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	% means inside 1 iteration
	ResetSaltFlat = 10,
	ResetSalt = StartSalt1+ResetSaltFlat,
	
	Salt1 = << StartSalt1:256 >>,
	{ok, Output1Part1, LastStepCheckpoints1Part1} = ar_mine_randomx:vdf_sha2_nif(Salt1, PrevOutput, ResetSaltFlat-1, 0, ?TEST_VDF_DIFFICULTY),
	MixOutput = reset_mix(Output1Part1, ResetSeed),
	Salt2 = << ResetSalt:256 >>,
	{ok, Output1Part2, LastStepCheckpoints1Part2} = ar_mine_randomx:vdf_sha2_nif(Salt2, MixOutput, ?VDF_CHECKPOINT_COUNT_IN_STEP-ResetSaltFlat-1, 0, ?TEST_VDF_DIFFICULTY),
	Output1 = Output1Part2,
	LastStepCheckpoints1 = <<LastStepCheckpoints1Part1/binary, Output1Part1/binary, LastStepCheckpoints1Part2/binary>>,
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),
	
	% partial verify should work
	BufferHash1 = Output1,
	FullBufferHash1 = <<LastStepCheckpoints1/binary, Output1/binary>>,
	{true, FullBufferHash1} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash1}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2 = Output2,
	FullBufferHash2 = <<LastStepCheckpoints2/binary, Output2/binary>>,
	{true, FullBufferHash2} = ar_vdf:verify(StartSalt2, Output1,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	<< Step1:?VDF_BYTE_SIZE/binary, Step2:?VDF_BYTE_SIZE/binary, _/binary >> = LastStepCheckpoints2,
	BufferHash3 = Step1,
	FullBufferHash3 = <<LastStepCheckpoints1/binary, Output1/binary, Step1/binary>>,
	{true, FullBufferHash3} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP+1, 1, BufferHash3}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash4 = Step2,
	FullBufferHash4 = <<LastStepCheckpoints1/binary, Output1/binary, Step1/binary, Step2/binary>>,
	{true, FullBufferHash4} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP+1+1, 1, BufferHash4}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash5 = <<Output1/binary, Output2/binary>>,
	FullBufferHash5 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, FullBufferHash5} = ar_vdf:verify(StartSalt1, PrevOutput,
		[{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash5}], ResetSalt, ResetSeed,
		?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

    % partial verify should work
    assert_verify(StartSalt1, ResetSalt, PrevOutput, 1, lists:reverse(Checkpoints1)),
    assert_verify(StartSalt2, ResetSalt, Output1, 1, lists:reverse(Checkpoints2)),

	Hash1 = lists:last(Checkpoints2),
	Hash2 = lists:nth(length(Checkpoints2) - 1, Checkpoints2),
    assert_verify(StartSalt1, ResetSalt, PrevOutput, 1, lists:reverse([Hash1 | Checkpoints1])),

    assert_verify(StartSalt1, ResetSalt, PrevOutput, 1, lists:reverse([Hash2, Hash1 | Checkpoints1])),

test_multigroup_regular_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartStepNumber3 = 4,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt3 = ar_vdf:step_number_to_salt_number(StartStepNumber3-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSalt = -1,
	
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, PrevOutput, ?TEST_VDF_DIFFICULTY),
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),
	{ok, Output3, LastStepCheckpoints3} = ar_vdf:compute(StartStepNumber3, Output2, ?TEST_VDF_DIFFICULTY),
	
	FullBufferHash = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	
	BufferHash1_1 = <<Output1/binary, Output2/binary>>,
	BufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	Groups1_1 = [
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	PartBufferHash1_1 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, PartBufferHash1_1} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_1, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_2 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2}
	],
	PartBufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	{true, PartBufferHash1_2} = ar_vdf:verify(StartSalt3, Output2, Groups1_2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_3 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_3, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2_1 = Output1,
	BufferHash2_2 = <<LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	Groups2 = [
		{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

test_multigroup_reset_0_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartStepNumber3 = 4,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt3 = ar_vdf:step_number_to_salt_number(StartStepNumber3-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSalt = StartSalt1,
	
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	MixOutput = reset_mix(PrevOutput, ResetSeed),
	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, MixOutput, ?TEST_VDF_DIFFICULTY),
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),
	{ok, Output3, LastStepCheckpoints3} = ar_vdf:compute(StartStepNumber3, Output2, ?TEST_VDF_DIFFICULTY),
	
	FullBufferHash = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	
	BufferHash1_1 = <<Output1/binary, Output2/binary>>,
	BufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	Groups1_1 = [
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	PartBufferHash1_1 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, PartBufferHash1_1} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_1, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_2 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2}
	],
	PartBufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	{true, PartBufferHash1_2} = ar_vdf:verify(StartSalt3, Output2, Groups1_2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_3 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_3, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2_1 = Output1,
	BufferHash2_2 = <<LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	Groups2 = [
		{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

test_multigroup_reset_1_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartStepNumber3 = 4,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	StartSalt3 = ar_vdf:step_number_to_salt_number(StartStepNumber3-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSalt = StartSalt2,
	
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, PrevOutput, ?TEST_VDF_DIFFICULTY),
	MixOutput = reset_mix(Output1, ResetSeed),
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, MixOutput, ?TEST_VDF_DIFFICULTY),
	{ok, Output3, LastStepCheckpoints3} = ar_vdf:compute(StartStepNumber3, Output2, ?TEST_VDF_DIFFICULTY),
	
	FullBufferHash = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	
	BufferHash1_1 = <<Output1/binary, Output2/binary>>,
	BufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	Groups1_1 = [
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	PartBufferHash1_1 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, PartBufferHash1_1} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_1, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_2 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2}
	],
	PartBufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	{true, PartBufferHash1_2} = ar_vdf:verify(StartSalt3, Output2, Groups1_2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_3 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_3, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2_1 = Output1,
	BufferHash2_2 = <<LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	Groups2 = [
		{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

test_multigroup_reset_2_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartStepNumber3 = 4,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt3 = ar_vdf:step_number_to_salt_number(StartStepNumber3-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSalt = StartSalt3,
	
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, PrevOutput, ?TEST_VDF_DIFFICULTY),
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),
	MixOutput = reset_mix(Output2, ResetSeed),
	{ok, Output3, LastStepCheckpoints3} = ar_vdf:compute(StartStepNumber3, MixOutput, ?TEST_VDF_DIFFICULTY),
	
	FullBufferHash = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	
	BufferHash1_1 = <<Output1/binary, Output2/binary>>,
	BufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	Groups1_1 = [
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	PartBufferHash1_1 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, PartBufferHash1_1} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_1, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_2 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2}
	],
	PartBufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	{true, PartBufferHash1_2} = ar_vdf:verify(StartSalt3, Output2, Groups1_2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_3 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_3, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2_1 = Output1,
	BufferHash2_2 = <<LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	Groups2 = [
		{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

test_multigroup_reset_0_plus_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartStepNumber3 = 4,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt3 = ar_vdf:step_number_to_salt_number(StartStepNumber3-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSaltFlat = 10,
	ResetSalt = StartSalt1+ResetSaltFlat,
	
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	
	Salt1 = << StartSalt1:256 >>,
	{ok, Output1Part1, LastStepCheckpoints1Part1} = ar_mine_randomx:vdf_sha2_nif(Salt1, PrevOutput, ResetSaltFlat-1, 0, ?TEST_VDF_DIFFICULTY),
	MixOutput = reset_mix(Output1Part1, ResetSeed),
	Salt2 = << ResetSalt:256 >>,
	{ok, Output1Part2, LastStepCheckpoints1Part2} = ar_mine_randomx:vdf_sha2_nif(Salt2, MixOutput, ?VDF_CHECKPOINT_COUNT_IN_STEP-ResetSaltFlat-1, 0, ?TEST_VDF_DIFFICULTY),
	Output1 = Output1Part2,
	LastStepCheckpoints1 = <<LastStepCheckpoints1Part1/binary, Output1Part1/binary, LastStepCheckpoints1Part2/binary>>,
	
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),
	{ok, Output3, LastStepCheckpoints3} = ar_vdf:compute(StartStepNumber3, Output2, ?TEST_VDF_DIFFICULTY),
	
	FullBufferHash = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	
	BufferHash1_1 = <<Output1/binary, Output2/binary>>,
	BufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	Groups1_1 = [
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	PartBufferHash1_1 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, PartBufferHash1_1} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_1, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_2 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2}
	],
	PartBufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	{true, PartBufferHash1_2} = ar_vdf:verify(StartSalt3, Output2, Groups1_2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_3 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_3, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	BufferHash2_1 = Output1,
	BufferHash2_2 = <<LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	Groups2 = [
		{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	
	ok.

test_multigroup_reset_1_plus_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartStepNumber3 = 4,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	StartSalt3 = ar_vdf:step_number_to_salt_number(StartStepNumber3-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),
	
	ResetSaltFlat = 10,
	ResetSalt = StartSalt2+ResetSaltFlat,
	
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	
	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, PrevOutput, ?TEST_VDF_DIFFICULTY),
	
	Salt1 = << StartSalt2:256 >>,
	{ok, Output2Part1, LastStepCheckpoints2Part1} = ar_mine_randomx:vdf_sha2_nif(Salt1, Output1, ResetSaltFlat-1, 0, ?TEST_VDF_DIFFICULTY),
	MixOutput = reset_mix(Output2Part1, ResetSeed),
	Salt2 = << ResetSalt:256 >>,
	{ok, Output2Part2, LastStepCheckpoints2Part2} = ar_mine_randomx:vdf_sha2_nif(Salt2, MixOutput, ?VDF_CHECKPOINT_COUNT_IN_STEP-ResetSaltFlat-1, 0, ?TEST_VDF_DIFFICULTY),
	Output2 = Output2Part2,
	LastStepCheckpoints2 = <<LastStepCheckpoints2Part1/binary, Output2Part1/binary, LastStepCheckpoints2Part2/binary>>,
	
	{ok, Output3, LastStepCheckpoints3} = ar_vdf:compute(StartStepNumber3, Output2, ?TEST_VDF_DIFFICULTY),
	
	FullBufferHash = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	
	BufferHash1_1 = <<Output1/binary, Output2/binary>>,
	% BufferHash1_1 = <<Output2/binary>>,
	BufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	Groups1_1 = [
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
		%{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash1_1}
	],
	PartBufferHash1_1 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, PartBufferHash1_1} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_1, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_2 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2}
	],
	PartBufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	{true, PartBufferHash1_2} = ar_vdf:verify(StartSalt3, Output2, Groups1_2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_3 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_3, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),

	BufferHash2_1 = Output1,
	BufferHash2_2 = <<LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	Groups2 = [
		{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),

    {ok, _Output2, Checkpoints2} = ar_vdf:compute2(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),

test_multigroup_reset_2_plus_() ->
	StartStepNumber1 = 2,
	StartStepNumber2 = 3,
	StartStepNumber3 = 4,
	StartSalt1 = ar_vdf:step_number_to_salt_number(StartStepNumber1-1),
	StartSalt2 = ar_vdf:step_number_to_salt_number(StartStepNumber2-1),
	StartSalt3 = ar_vdf:step_number_to_salt_number(StartStepNumber3-1),
	PrevOutput = ar_util:decode(?ENCODED_PREV_OUTPUT),
	ResetSeed = ar_util:decode(?RESET_SEED),

	ResetSaltFlat = 10,
	ResetSalt = StartSalt3+ResetSaltFlat,

    assert_verify(StartSalt1, ResetSalt, PrevOutput, 1, lists:reverse([Hash2, Hash1 | Checkpoints1])),

	{ok, Output1, LastStepCheckpoints1} = ar_vdf:compute(StartStepNumber1, PrevOutput, ?TEST_VDF_DIFFICULTY),
	{ok, Output2, LastStepCheckpoints2} = ar_vdf:compute(StartStepNumber2, Output1, ?TEST_VDF_DIFFICULTY),

	Salt1 = << StartSalt3:256 >>,
	{ok, Output3Part1, LastStepCheckpoints3Part1} = ar_mine_randomx:vdf_sha2_nif(Salt1, Output2, ResetSaltFlat-1, 0, ?TEST_VDF_DIFFICULTY),
	MixOutput = reset_mix(Output3Part1, ResetSeed),
	Salt2 = << ResetSalt:256 >>,
	{ok, Output3Part2, LastStepCheckpoints3Part2} = ar_mine_randomx:vdf_sha2_nif(Salt2, MixOutput, ?VDF_CHECKPOINT_COUNT_IN_STEP-ResetSaltFlat-1, 0, ?TEST_VDF_DIFFICULTY),
	Output3 = Output3Part2,
	LastStepCheckpoints3 = <<LastStepCheckpoints3Part1/binary, Output3Part1/binary, LastStepCheckpoints3Part2/binary>>,

	FullBufferHash = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,

	BufferHash1_1 = <<Output1/binary, Output2/binary>>,
	% BufferHash1_1 = <<Output2/binary>>,
	BufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	Groups1_1 = [
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
		%{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash1_1}
	],
	PartBufferHash1_1 = <<LastStepCheckpoints1/binary, Output1/binary, LastStepCheckpoints2/binary, Output2/binary>>,
	{true, PartBufferHash1_1} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_1, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_2 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2}
	],
	PartBufferHash1_2 = <<LastStepCheckpoints3/binary, Output3/binary>>,
	{true, PartBufferHash1_2} = ar_vdf:verify(StartSalt3, Output2, Groups1_2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),
	Groups1_3 = [
		{1, ?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash1_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 2, BufferHash1_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups1_3, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),

	BufferHash2_1 = Output1,
	BufferHash2_2 = <<LastStepCheckpoints2/binary, Output2/binary, LastStepCheckpoints3/binary, Output3/binary>>,
	Groups2 = [
		{1, 2*?VDF_CHECKPOINT_COUNT_IN_STEP, BufferHash2_2},
		{?VDF_CHECKPOINT_COUNT_IN_STEP, 1, BufferHash2_1}
	],
	{true, FullBufferHash} = ar_vdf:verify(StartSalt1, PrevOutput, Groups2, ResetSalt, ResetSeed, ?MAX_THREAD_COUNT, ?TEST_VDF_DIFFICULTY),

    ok.