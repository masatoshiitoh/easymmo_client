-module(player1).
-include_lib("amqp_client.hrl").

-export([start_link/3]).
-export([terminate/2]).
-export([init/1, handle_call/3]).
-export([handle_info/2]).

-export([move/2]).

%%
start_link(ServerIp, ToClientEx, FromClientEx) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [ServerIp, ToClientEx, FromClientEx], []).

init(Args) ->
    [ServerIp, ToClientEx, FromClientEx] = Args,
    {Connection, ChTC, ChFC} = setup_connection(ServerIp, ToClientEx, FromClientEx),
    NewState = {ServerIp, ToClientEx, FromClientEx, {Connection, ChTC, ChFC}},
    {ok, NewState}.

%%
%% APIs
%%

move(X, Y) ->
	gen_server:call(?MODULE, {send, io_lib:format("move ~p ~p~n", [X,Y])}).

%%
%% Internal use.
%%
setup_connection(ServerIp, ToClientEx, FromClientEx) ->
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

%% just after setup, this message will arrive.
handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};

%% while subscribing, message will be delivered by #amqp_msg
handle_info( {#'basic.deliver'{}, #amqp_msg{payload = Body}} , State) ->
    {ServerIp, ToClientEx, FromClientEx, {Connection, ChTC, ChFC}} = State,
	io:format("Received. ~p~n", [binary_to_list(Body)]),
    {noreply, State}.

handle_call({send, Text}, From, State) when is_list(Text) ->
	handle_call({send, list_to_binary(Text)}, From, State);

handle_call({send, Message}, From, State) when is_binary(Message) ->
	{ServerIp, ToClientEx, FromClientEx, {Connection, ChTC, ChFC}} = State,
    % エクスチェンジにメッセージ送信。
    amqp_channel:cast(ChFC,
		#'basic.publish'{exchange = FromClientEx},
		#amqp_msg{payload = Message}),
    io:format("Sent ~p~n", [binary_to_list(Message)]),
    {reply, ok, State}.




