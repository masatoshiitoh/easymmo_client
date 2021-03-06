-module(easymmo_client_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
	ChildSpec = [
	client()
	],
    {ok, { {one_for_one, 5, 10}, ChildSpec} }.


client() ->
    client_one("localhost", <<"xout">>, <<"xin">> ).

client_one(ServerIp, ToClientEx, FromClientEx) ->
    ID = move_srv,
    StartFunc = {player1, start_link, [ServerIp, ToClientEx, FromClientEx]},
    Restart = permanent,
    Shutdown = brutal_kill,
    Type = worker,
    Modules = [player1],
    _ChildSpec = {ID, StartFunc, Restart, Shutdown, Type, Modules}.

