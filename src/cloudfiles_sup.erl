%%%----------------------------------------------------------------
%%% @author  Kai Janson <kai.janson@rackspace.com>
%%% @doc
%%% @end
%%% @copyright 2012 Kai Janson
%%%----------------------------------------------------------------
-module(cloudfiles_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

-spec start_link() -> {ok, pid()} | any().
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================


%% @private
-spec init(list()) -> {ok, {SupFlags::any(), [ChildSpec::any()]}} |
                       ignore | {error, Reason::any()}.
init([]) ->
    RestartStrategy = one_for_one,
    MaxRestarts = 1000,
    MaxSecondsBetweenRestarts = 3600,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    Restart = permanent,
    Shutdown = 2000,
    Type = worker,

    AChild = {cloudfiles, {cloudfiles, start_link, []},
              Restart, Shutdown, Type, [cloudfiles]},

    {ok, {SupFlags, [AChild]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%%====================================================================
%%% tests
%%%====================================================================
