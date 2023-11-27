-module(ar_sync_record_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-include_lib("arweave/include/ar_sup.hrl").
-include_lib("arweave/include/ar_config.hrl").

%%%===================================================================
%%% Public interface.
%%%===================================================================

start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks.
%% ===================================================================

init([]) ->
	{ok, Config} = application:get_env(arweave, config),
	ConfiguredWorkers = lists:map(
		fun(StorageModule) ->
			StoreID = ar_storage_module:id(StorageModule),
			Name = list_to_atom("ar_sync_record_" ++ StoreID),
			?CHILD_WITH_ARGS(ar_sync_record, worker, Name, [Name, StoreID])
		end,
		Config#config.storage_modules
	),
	DefaultSyncRecordWorker = ?CHILD_WITH_ARGS(ar_sync_record, worker, ar_sync_record_default,
		[ar_sync_record_default, "default"]), 
	Workers = [DefaultSyncRecordWorker | ConfiguredWorkers],
	{ok, {{one_for_one, 5, 10}, Workers}}.
