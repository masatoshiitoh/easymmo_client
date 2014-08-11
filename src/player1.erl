-module(player1).
-include_lib("amqp_client.hrl").

-export([start_link/0]).
-export([terminate/2]).
-export([init/1, handle_call/3]).
-export([handle_info/2]).

-export([run/0]).
-export([stop/0]).
-export([move/2]).

%%
%% 待ち受けループをspawnする。
%% 待ち受けループをgen_server経由で止める？？
%% 個別メッセージをgen_serverでおくる
%%

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init(_Args) ->
	{ok, []}.

%%
%% APIs
%%

%% エクスチェンジ名等は開始時にサーバ側で保存させる。
%% moveAPIなどはそのまま値だけ渡せば良い。
%% 受信ループは、手元のプロセスとして起動する。
start_service(ServerIp, ToClientEx, FromClientEx)
	when is_binary(ToClientEx), is_binary(FromClientEx) ->
	Reply = gen_server:call(?MODULE, {start_service, ServerIp, ToClientEx, FromClientEx}).

run() ->
	start_service("27.120.111.23", <<"xout">>, <<"xin">>),
	ok.

stop() ->
	Reply = gen_server:cast(?MODULE, stop).

move(X, Y) ->
	Reply = gen_server:call(?MODULE, {send, io_lib:format("move ~p ~p~n", [X,Y])}).

%%
%% Internal use.
%%

setup_connection(ServerIp, ToClientEx2, FromClientEx) ->
	ToClientEx = <<"time">>,
    % コネクション開く
    {ok, Connection} =
        amqp_connection:start(#amqp_params_network{host = ServerIp}),

    %% 送信用(exchange name = FromClientEx, channel = ChFC)
    % チャネル開く
    {ok, ChFC} = amqp_connection:open_channel(Connection),
    % エクスチェンジを宣言
    amqp_channel:call(ChFC, #'exchange.declare'{exchange = FromClientEx, type = <<"fanout">>}),

    %% 受信用(exchange name = ToClientEx, channel = ChTC)
    % OUTチャネルを開く
    {ok, ChTC} = amqp_connection:open_channel(Connection),
    % エクスチェンジを宣言
    amqp_channel:call(ChTC, #'exchange.declare'{exchange = ToClientEx, type = <<"fanout">>}),
    % クライアント宛キューを宣言する。
    #'queue.declare_ok'{queue = Queue} = amqp_channel:call(ChTC, #'queue.declare'{exclusive = true}),
    % 指定のエクスチェンジに受信キューをバインドする。
    amqp_channel:call(ChTC, #'queue.bind'{exchange = ToClientEx, queue = Queue}),
    % 指定のキューの購読開始。
    amqp_channel:subscribe(ChTC, #'basic.consume'{queue = Queue, no_ack = true}, self()),

    % ok待ち
    io:format(" [*] Waiting for logs. To exit press CTRL+C~n"),
    receive
        #'basic.consume_ok'{} -> ok
    end,

	{Connection, ChTC, ChFC}.

shutdown_connect(Connection, ChTC, ChFC) ->
    % チャネル閉じる。
    ok = amqp_channel:close(ChFC),
    % チャネル閉じる。
    ok = amqp_channel:close(ChTC),
    % コネクション閉じる。
    ok = amqp_connection:close(Connection),
	ok.

%% gen_server behaviour %%
terminate(Reason, State) ->
	{ServerIp, ToClientEx, FromClientEx, {Connection, ChTC, ChFC}} = State,
	%% コネクション停止
	shutdown_connect(Connection, ChTC, ChFC),
    ok.

handle_info( {#'basic.deliver'{}, #amqp_msg{payload = Body}} , State) ->
	io:format(" [x] ~p~n", [Body]),
	{noreply, State};

handle_info("stop", State) ->
	{ServerIp, ToClientEx, FromClientEx, {Connection, ChTC, ChFC}} = State,
	shutdown_connect(Connection, ChTC, ChFC),
	{stop, ok, State}.

handle_call({start_service, ServerIp, ToClientEx, FromClientEx}, From, State) ->
	{Connection, ChTC, ChFC} = setup_connection(ServerIp, ToClientEx, FromClientEx),
	NewState = {ServerIp, ToClientEx, FromClientEx, {Connection, ChTC, ChFC}},
    {reply, ok, NewState};

handle_call({send, Text}, From, State) when is_list(Text) ->
	handle_call({send, list_to_binary(Text)}, From, State);

handle_call({send, Message}, From, State) when is_binary(Message) ->
	{ServerIp, ToClientEx, FromClientEx, {Connection, ChTC, ChFC}} = State,
    %% Message = <<"player1: Hello World!">>,
    % エクスチェンジにメッセージ送信。
    amqp_channel:cast(ChFC,
		#'basic.publish'{exchange = FromClientEx},
		#amqp_msg{payload = Message}),
    io:format("Sent ~p~n", [binary_to_list(Message)]),
    {reply, ok, State}.





