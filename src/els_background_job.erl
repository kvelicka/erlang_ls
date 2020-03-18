%%==============================================================================
%% Background Job Server
%%==============================================================================
-module(els_background_job).

%%==============================================================================
%% API
%%==============================================================================
-export([ start_link/1 ]).

%%==============================================================================
%% Callbacks for gen_server
%%==============================================================================
-behaviour(gen_server).
-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        ]).

%%==============================================================================
%% Types
%%==============================================================================
-type entry() :: any().
-type config() :: #{ task := fun((entry()) -> ok)
                   , entries := [any()]
                   , on_complete => fun()
                     %% TODO: Add label
                   }.
-type state() :: #{config := config()}.

%%==============================================================================
%% API
%%==============================================================================
-spec start_link(config()) -> {ok, pid()}.
start_link(Config) ->
  gen_server:start_link(?MODULE, Config, []).

%%==============================================================================
%% Callbacks for gen_server
%%==============================================================================
-spec init(config()) -> {ok, state()}.
init(Config) ->
  self() ! init,
  {ok, #{config => Config}}.

-spec handle_call(any(), {pid(), any()}, state()) ->
  {noreply, state()}.
handle_call(_Request, _From, State) ->
  {noreply, State}.

-spec handle_cast(any(), any()) ->
  {noreply, state()}.
handle_cast(_Request, State) ->
  {noreply, State}.

-spec handle_info(any(), any()) ->
  {noreply, state()}.
handle_info(init, State) ->
  #{config := Config} = State,
  #{task := Task, entries := Entries} = Config,
  %% TODO: If supported
  Title = <<"Indexing">>,
  Total = length(Entries),
  Step = step(Total),
  Token = els_work_done_progress:send_create_request(),
  BeginMsg = progress_msg(0, Total),
  Begin = els_work_done_progress:value_begin(Title, BeginMsg, 0),
  els_progress:send_notification(Token, Begin),
  F = fun(Entry, Progress) ->
          %% TODO: Handle failures, eg log, add test
          Task(Entry),
          Percentage = floor(Progress * Step),
          ReportMsg = progress_msg(Progress, Total),
          Report = els_work_done_progress:value_report(ReportMsg, Percentage),
          els_progress:send_notification(Token, Report),
          Progress + 1
      end,
  _Res = lists:foldl(F, 1, Entries),
  case maps:is_key(on_complete, Config) of
    true ->
      OnCompleteFun = maps:get(on_complete, Config),
      OnCompleteFun();
    false ->
      ok
  end,
  EndMsg = progress_msg(Total, Total),
  End = els_work_done_progress:value_end(EndMsg),
  els_progress:send_notification(Token, End),
  {stop, normal, State};
handle_info(_Request, State) ->
  {noreply, State}.

%%==============================================================================
%% Internal functions
%%==============================================================================
-spec step(pos_integer()) -> pos_integer().
step(0) -> 0;
step(N) -> 100 / N.

-spec progress_msg(pos_integer(), pos_integer()) -> binary().
progress_msg(Current, Total) ->
  list_to_binary(io_lib:format("~p / ~p", [Current, Total])).
