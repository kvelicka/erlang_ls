-module(els_diagnostics_SUITE).

%% CT Callbacks
-export([ suite/0
        , init_per_suite/1
        , end_per_suite/1
        , init_per_testcase/2
        , end_per_testcase/2
        , groups/0
        , all/0
        ]).

%% Test cases
-export([ compiler/1
        , compiler_with_behaviour/1
        , compiler_with_custom_macros/1
        , compiler_with_parse_transform/1
        , compiler_with_parse_transform_included/1
        , code_reload/1
        , code_reload_sticky_mod/1
        , elvis/1
        , escript/1
        , escript_warnings/1
        , escript_errors/1
        ]).

%%==============================================================================
%% Includes
%%==============================================================================
-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("erlang_ls.hrl").

%%==============================================================================
%% Types
%%==============================================================================
-type config() :: [{atom(), any()}].

%%==============================================================================
%% CT Callbacks
%%==============================================================================
-spec suite() -> [tuple()].
suite() ->
  [{timetrap, {seconds, 30}}].

-spec all() -> [{group, stdio | tcp}].
all() ->
  [{group, tcp}, {group, stdio}].

-spec groups() -> [atom()].
groups() ->
  els_test_utils:groups(?MODULE).

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
  els_test_utils:init_per_suite(Config).

-spec end_per_suite(config()) -> ok.
end_per_suite(Config) ->
  els_test_utils:end_per_suite(Config).

-spec init_per_testcase(atom(), config()) -> config().
init_per_testcase(TestCase, Config) when TestCase =:= code_reload orelse
                                         TestCase =:= code_reload_sticky_mod ->
  mock_rpc(),
  mock_code_reload_enabled(),
  els_test_utils:init_per_testcase(TestCase, Config);
init_per_testcase(TestCase, Config) ->
  els_mock_diagnostics:setup(),
  els_test_utils:init_per_testcase(TestCase, Config).

-spec end_per_testcase(atom(), config()) -> ok.
end_per_testcase(TestCase, Config) when TestCase =:= code_reload orelse
                                        TestCase =:= code_reload_sticky_mod ->
  unmock_rpc(),
  unmock_code_reload_enabled(),
  els_test_utils:end_per_testcase(TestCase, Config);
end_per_testcase(TestCase, Config) ->
  els_test_utils:end_per_testcase(TestCase, Config),
  els_mock_diagnostics:teardown(),
  ok.

%%==============================================================================
%% Testcases
%%==============================================================================
-spec compiler(config()) -> ok.
compiler(Config) ->
  Uri = ?config(diagnostics_uri, Config),
  els_mock_diagnostics:subscribe(),
  ok = els_client:did_save(Uri),
  Diagnostics = els_mock_diagnostics:wait_until_complete(),
  ?assertEqual(4, length(Diagnostics)),
  Warnings = [D || #{severity := ?DIAGNOSTIC_WARNING} = D <- Diagnostics],
  Errors   = [D || #{severity := ?DIAGNOSTIC_ERROR}   = D <- Diagnostics],
  ?assertEqual(1, length(Warnings)),
  ?assertEqual(3, length(Errors)),
  WarningRanges = [ Range || #{range := Range} <- Warnings],
  ExpectedWarningRanges = [ #{'end' => #{character => 0, line => 7},
                              start => #{character => 0, line => 6}}
                          ],
  ?assertEqual(ExpectedWarningRanges, WarningRanges),
  ErrorRanges = [ Range || #{range := Range} <- Errors],
  ExpectedErrorRanges = [ #{'end' => #{character => 35, line => 3},
                            start => #{character => 0, line => 3}},
                          #{'end' => #{character => 35, line => 3},
                            start => #{character => 0, line => 3}},
                          #{'end' => #{character => 0, line => 6},
                            start => #{character => 0, line => 5}}
                        ],
  ?assertEqual(ExpectedErrorRanges, ErrorRanges),
  ok.

-spec compiler_with_behaviour(config()) -> ok.
compiler_with_behaviour(Config) ->
  Uri = ?config(diagnostics_behaviour_impl_uri, Config),
  els_mock_diagnostics:subscribe(),
  ok = els_client:did_save(Uri),
  Diagnostics = els_mock_diagnostics:wait_until_complete(),
  ?assertEqual(2, length(Diagnostics)),
  Warnings = [D || #{severity := ?DIAGNOSTIC_WARNING} = D <- Diagnostics],
  ?assertEqual(2, length(Warnings)),
  ErrorRanges = [ Range || #{range := Range} <- Warnings],
  ExpectedErrorRanges = [ #{ 'end' => #{character => 0, line => 3}
                           , start => #{character => 0, line => 2}}
                        , #{ 'end' => #{character => 0, line => 3}
                           , start => #{character => 0, line => 2}}
                        ],
  ?assertEqual(ExpectedErrorRanges, ErrorRanges),
  ok.

-spec compiler_with_custom_macros(config()) -> ok.
compiler_with_custom_macros(Config) ->
  Uri = ?config(diagnostics_macros_uri, Config),
  els_mock_diagnostics:subscribe(),
  ok = els_client:did_save(Uri),
  Diagnostics = els_mock_diagnostics:wait_until_complete(),
  ?assertEqual(1, length(Diagnostics)),
  Errors   = [D || #{severity := ?DIAGNOSTIC_ERROR}   = D <- Diagnostics],
  ?assertEqual(1, length(Errors)),
  ErrorRanges = [ Range || #{range := Range} <- Errors],
  ExpectedErrorRanges = [ #{ 'end' => #{character => 0, line => 9}
                           , start => #{character => 0, line => 8}}
                        ],
  ?assertEqual(ExpectedErrorRanges, ErrorRanges),
  ok.

-spec compiler_with_parse_transform(config()) -> ok.
compiler_with_parse_transform(Config) ->
  Uri = ?config(diagnostics_parse_transform_usage_uri, Config),
  els_mock_diagnostics:subscribe(),
  ok = els_client:did_save(Uri),
  Diagnostics = els_mock_diagnostics:wait_until_complete(),
  ?assertEqual(1, length(Diagnostics)),
  Warnings = [D || #{severity := ?DIAGNOSTIC_WARNING} = D <- Diagnostics],
  ?assertEqual(1, length(Warnings)),
  WarningRanges = [ Range || #{range := Range} <- Warnings],
  ExpectedWarningsRanges = [ #{ 'end' => #{character => 0, line => 7}
                              , start => #{character => 0, line => 6}}
                           ],
  ?assertEqual(ExpectedWarningsRanges, WarningRanges),
  ok.

-spec compiler_with_parse_transform_included(config()) -> ok.
compiler_with_parse_transform_included(Config) ->
  Uri = ?config(diagnostics_parse_transform_usage_included_uri, Config),
  els_mock_diagnostics:subscribe(),
  ok = els_client:did_save(Uri),
  Diagnostics = els_mock_diagnostics:wait_until_complete(),
  ?assertEqual(1, length(Diagnostics)),
  Warnings = [D || #{severity := ?DIAGNOSTIC_WARNING} = D <- Diagnostics],
  ?assertEqual(1, length(Warnings)),
  WarningRanges = [ Range || #{range := Range} <- Warnings],
  ExpectedWarningsRanges = [ #{ 'end' => #{character => 0, line => 7}
                              , start => #{character => 0, line => 6}}
                           ],
  ?assertEqual(ExpectedWarningsRanges, WarningRanges),
  ok.

-spec elvis(config()) -> ok.
elvis(Config) ->
  {ok, Cwd} = file:get_cwd(),
  RootPath = ?config(root_path, Config),
  try
      file:set_cwd(RootPath),
      Uri = ?config(elvis_diagnostics_uri, Config),
      els_mock_diagnostics:subscribe(),
      ok = els_client:did_save(Uri),
      Diagnostics = els_mock_diagnostics:wait_until_complete(),
      CDiagnostics = [D|| #{source := <<"Compiler">>} = D <- Diagnostics],
      EDiagnostics = [D|| #{source := <<"Elvis">>} = D <- Diagnostics],
      ?assertEqual(0, length(CDiagnostics)),
      ?assertEqual(2, length(EDiagnostics)),
      Warnings = [D || #{severity := ?DIAGNOSTIC_WARNING} = D <- EDiagnostics],
      Errors   = [D || #{severity := ?DIAGNOSTIC_ERROR}   = D <- EDiagnostics],
      ?assertEqual(2, length(Warnings)),
      ?assertEqual(0, length(Errors)),
      [ #{range := WarningRange1}
      , #{range := WarningRange2} ] = Warnings,
      ?assertEqual( #{'end' => #{character => 0, line => 6},
                      start => #{character => 0, line => 5}}
                  , WarningRange1
                  ),
      ?assertEqual( #{'end' => #{character => 0, line => 7},
                      start => #{character => 0, line => 6}}
                  , WarningRange2
                  )
  catch _Err ->
      file:set_cwd(Cwd)
  end,
  ok.

-spec escript(config()) -> ok.
escript(Config) ->
  Uri = ?config(diagnostics_escript_uri, Config),
  els_mock_diagnostics:subscribe(),
  ok = els_client:did_save(Uri),
  Diagnostics = els_mock_diagnostics:wait_until_complete(),
  ?assertEqual([], Diagnostics),
  ok.

-spec escript_warnings(config()) -> ok.
escript_warnings(Config) ->
  Uri = ?config(diagnostics_warnings_escript_uri, Config),
  els_mock_diagnostics:subscribe(),
  ok = els_client:did_save(Uri),
  Diagnostics = els_mock_diagnostics:wait_until_complete(),
  ?assertEqual(1, length(Diagnostics)),
  Warnings = [D || #{severity := ?DIAGNOSTIC_WARNING} = D <- Diagnostics],
  Errors   = [D || #{severity := ?DIAGNOSTIC_ERROR}   = D <- Diagnostics],
  ?assertEqual([], Errors),
  ?assertEqual(1, length(Warnings)),
  WarningRanges = [ Range || #{range := Range} <- Warnings],
  ExpectedWarningRanges = [ #{'end' => #{character => 0, line => 24},
                              start => #{character => 0, line => 23}}
                          ],
  ?assertEqual(ExpectedWarningRanges, WarningRanges),
  ok.

-spec escript_errors(config()) -> ok.
escript_errors(Config) ->
  Uri = ?config(diagnostics_errors_escript_uri, Config),
  els_mock_diagnostics:subscribe(),
  ok = els_client:did_save(Uri),
  Diagnostics = els_mock_diagnostics:wait_until_complete(),
  ?assertEqual(1, length(Diagnostics)),
  Warnings = [D || #{severity := ?DIAGNOSTIC_WARNING} = D <- Diagnostics],
  Errors   = [D || #{severity := ?DIAGNOSTIC_ERROR}   = D <- Diagnostics],
  ?assertEqual([], Warnings),
  ?assertEqual(1, length(Errors)),
  ErrorRanges = [ Range || #{range := Range} <- Errors],
  ExpectedErrorRanges = [ #{'end' => #{character => 0, line => 24},
                            start => #{character => 0, line => 23}}
                        ],
  ?assertEqual(ExpectedErrorRanges, ErrorRanges),
  ok.

-spec code_reload(config()) -> ok.
code_reload(Config) ->
  Uri = ?config(diagnostics_uri, Config),
  Module = els_uri:module(Uri),
  ok = els_compiler_diagnostics:on_complete(Uri, []),
  ?assert(meck:called(rpc, call, ['fakenode', c, c, [Module]])),
  ok.

-spec code_reload_sticky_mod(config()) -> ok.
code_reload_sticky_mod(Config) ->
  Uri = ?config(diagnostics_uri, Config),
  Module = els_uri:module(Uri),
  meck:expect( rpc
             , call
             , fun('fakenode', code, is_sticky, [_]) ->
                   true;
                  (Node, Mod, Fun, Args) ->
                   meck:passthrough([Node, Mod, Fun, Args])
               end
             ),
  ok = els_compiler_diagnostics:on_complete(Uri, []),
  ?assert(meck:called(rpc, call, ['fakenode', code, is_sticky, [Module]])),
  ?assertNot(meck:called(rpc, call, ['fakenode', c, c, [Module]])),
  ok.

%%==============================================================================
%% Internal Functions
%%==============================================================================

mock_rpc() ->
  meck:new(rpc, [passthrough, no_link, unstick]),
  meck:expect( rpc
             , call
             , fun('fakenode', c, c, [Module]) ->
                   {ok, Module};
                  (Node, Mod, Fun, Args) ->
                   meck:passthrough([Node, Mod, Fun, Args])
               end
             ).

unmock_rpc() ->
  meck:unload(rpc).

mock_code_reload_enabled() ->
  meck:new(els_config, [passthrough, no_link]),
  meck:expect( els_config
             , get
             , fun(code_reload) ->
                   #{"node" => "fakenode"};
                  (Key) ->
                   meck:passthrough([Key])
               end
             ).

unmock_code_reload_enabled() ->
  meck:unload(els_config).
