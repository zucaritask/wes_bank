-module(wes_bank_elli_handler).

-behaviour(elli_handler).

-include_lib("elli/include/elli.hrl").

-export([handle/2,
         handle_event/3]).

handle(Req, _Args) ->
    case elli_request:get_header(<<"User-Id">>, Req) of
        undefined ->
            error_logger:error_msg("No user id header ~p",
                                   [elli_request:headers(Req)]),
            throw({400, [], <<"">>});
        Session ->
            try
                wes_bank:start_session(Session),
                dispatch(Req#req.method, elli_request:path(Req), Session, Req)
            catch
                error:channel_not_started ->
                    error_logger:error_msg("Channel not started ~p", [Session]),
                    throw({400, [], <<"">>})
            end
    end.

dispatch('POST', [Account], Session, _Req) ->
    %% This creates a bank account.
    wes_bank:create_account(Session, Account),
    {204, [], <<"">>};
dispatch('POST', [Account, <<"insert">>], Session, Req) ->
    [Amount] = args([amount], Req),
    wes_bank:open_account(Session, Account),
    ok = wes_bank:insert(Session, Account, Amount),
    {204, [], <<"">>};
dispatch('POST', [Account, <<"withdraw">>], Session, Req) ->
    [Amount] = args([amount], Req),
    wes_bank:open_account(Session, Account),
    ok = wes_bank:withdraw(Session, Account, Amount),
    {204, [], <<"">>};
dispatch('POST', [From, <<"transfer">>], Session, Req) ->
    [To, Amount] = args([to, amount], Req),
    FromResult = wes_bank:open_account(Session, From),
    ToResult = wes_bank:open_account(Session, To),
    case {FromResult, ToResult} of
        {ok, ok} ->
            ok = wes_bank:transfer(Session, From, To, Amount),
            {204, [], <<>>};
        {_, _} ->
            {409, [], <<>>}
    end;
dispatch('GET', [Account, <<"balance">>], Session, _Req) ->
    wes_bank:open_account(Session, Account),
    Value = wes_bank:balance(Session, Account),
    {200, [{<<"Content-Type">>, <<"application/json">>}],
     jiffy:encode({[{balance, Value}]})};
dispatch(_, _, _, _) -> ignore.


handle_event(request_closed, _Data, _Args) ->
    ok;
handle_event(request_complete, _Data, _Args) ->
    ok;
handle_event(Event, Data, _Args) ->
    error_logger:info_msg("Event ~p: ~p", [Event, Data]),
    ok.

args(Args, Req) ->
    {Props} = parse_body(Req),
    lists:map(
      fun(Arg) ->
              case lists:keyfind(atom_to_binary(Arg, utf8), 1, Props) of
                  {_, Value} -> Value;
                  false ->
                      error_logger:error_msg("Missing argument ~p: ~p",
                                             [Arg, Props]),
                      throw({400, [], <<"">>})
              end
      end,
      Args).

parse_body(Req) ->
    try
        jiffy:decode(elli_request:body(Req))
    catch
        throw:Reason ->
            error_logger:error_msg("Parse error ~p", [Reason]),
            throw({400, [], <<"">>})
    end.
