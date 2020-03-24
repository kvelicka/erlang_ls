-module(els_execute_command_provider).

-behaviour(els_provider).

-export([ handle_request/2
        , is_enabled/0
        , options/0
        ]).

-include("erlang_ls.hrl").

%%==============================================================================
%% els_provider functions
%%==============================================================================

-spec is_enabled() -> boolean().
is_enabled() -> true.

-spec options() -> map().
options() ->
  #{ commands => [ els_command:with_prefix(<<"replace-lines">>)
                 , els_command:with_prefix(<<"server-info">>)
                 , els_command:with_prefix(<<"ct-run-test">>)
                 ] }.

-spec handle_request(any(), els_provider:state()) ->
  {any(), els_provider:state()}.
handle_request({workspace_executecommand, Params}, State) ->
  #{ <<"command">> := PrefixedCommand } = Params,
  Arguments = maps:get(<<"arguments">>, Params, []),
  Result = execute_command( els_command:without_prefix(PrefixedCommand)
                          , Arguments),
  {Result, State}.

%%==============================================================================
%% Internal Functions
%%==============================================================================

-spec execute_command(els_command:command_id(), [any()]) -> [map()].
execute_command(<<"replace-lines">>
               , [#{ <<"uri">>   := Uri
                   , <<"lines">> := Lines
                   , <<"from">>  := LineFrom
                   , <<"to">>    := LineTo }]) ->
  Method = <<"workspace/applyEdit">>,
  Params = #{ edit =>
                  els_text_edit:edit_replace_text(Uri, Lines, LineFrom, LineTo)
            },
  els_server:send_request(Method, Params),
  [];
execute_command(<<"server-info">>, _Arguments) ->
  {ok, Version} = application:get_key(?APP, vsn),
  BinVersion = list_to_binary(Version),
  Root = filename:basename(els_uri:path(els_config:get(root_uri))),
  ConfigPath = case els_config:get(config_path) of
                 undefined -> <<"undefined">>;
                 Path -> list_to_binary(Path)
               end,
  Message = <<"Erlang LS (in ", Root/binary, "), version: "
             , BinVersion/binary
             , ", config from "
             , ConfigPath/binary
            >>,
  els_server:send_notification(<<"window/showMessage">>,
                               #{ type => ?MESSAGE_TYPE_INFO,
                                  message => Message
                                }),
  [];
execute_command(<<"ct-run-test">>, [#{ <<"module">> := Module
                                     , <<"function">> := Function
                                     , <<"arity">> := Arity
                                     , <<"line">> := Line
                                     , <<"uri">> := Uri
                                     }]) ->
  lager:info("Running CT test [module=~s] [function=~s] [arity=~p]", [ Module
                                                                     , Function
                                                                     , Arity]),
  Title = unicode:characters_to_binary(
            io_lib:format( "Running CT test for ~p:~p/~p"
                         , [Module, Function, Arity])),
  Config = #{ task => fun({_M, F, _A}) ->
                          Opts = [ {suite, [binary_to_list(els_uri:path(Uri))]}
                                 , {testcase, [binary_to_atom(F, utf8)]}
                                 , {include, els_config:get(include_paths)}
                                 , {auto_compile, true}
                                   %% TODO: Add support for groups
                                   %% TODO: Where to show logs?
                                 , {logdir, "/tmp/pigeon"}
                                 , {ct_hooks, [{els_cth, #{ uri => Uri
                                                          , line => Line}}]}
                                 ],
                          Result = ct:run_test(Opts),
                          lager:info("CT Result: ~p", [Result]),
                          case Result of
                            {N, 0, {0, 0}} when N > 0 ->
                              Range = els_protocol:range( #{ from => {Line, 1}
                                                           , to => {Line + 1, 1}
                                                           }),
                              Message = <<"Test passed">>,
                              Diagnostic =
                                els_diagnostics:make_diagnostic(Range
                                                               , Message
                                                               , ?DIAGNOSTIC_HINT
                                                               , <<"Common Test">>
                                                               ),
                              els_diagnostics:publish(Uri, [Diagnostic]);
                            _ ->
                              ok
                          end
                      end
            , entries => [{Module, Function, Arity}]
            , title => Title
            , on_complete => fun() -> ok end
            , on_error => fun() -> ok end
            },
  els_background_job:new(Config),
  [];
execute_command(Command, Arguments) ->
  lager:info("Unsupported command: [Command=~p] [Arguments=~p]"
            , [Command, Arguments]),
  [].
