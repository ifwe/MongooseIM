%%%----------------------------------------------------------------------
%%% File    : adhoc.erl
%%% Author  : Magnus Henoch <henoch@dtek.chalmers.se>
%%% Purpose : Provide helper functions for ad-hoc commands (XEP-0050)
%%% Created : 31 Oct 2005 by Magnus Henoch <henoch@dtek.chalmers.se>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2011   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------

-module(adhoc).
-author('henoch@dtek.chalmers.se').

-export([parse_request/1,
         produce_response/2,
         produce_response/1]).

-include("ejabberd.hrl").
-include("jlib.hrl").
-include("adhoc.hrl").

-type request() :: #adhoc_request{}.
-type response() :: #adhoc_response{}.

-export_type([request/0, response/0]).

%% @doc Parse an ad-hoc request.  Return either an adhoc_request record or
%% an {error, ErrorType} tuple.
-spec parse_request(ejabberd:iq()) -> request() | {error, jlib:xmlel()}.
parse_request(#iq{type = set, lang = Lang, sub_el = SubEl, xmlns = ?NS_COMMANDS}) ->
    ?DEBUG("entering parse_request...", []),
    Node = xml:get_tag_attr_s(<<"node">>, SubEl),
    SessionID = xml:get_tag_attr_s(<<"sessionid">>, SubEl),
    Action = xml:get_tag_attr_s(<<"action">>, SubEl),
    XData = find_xdata_el(SubEl),
    #xmlel{children = AllEls} = SubEl,
    Others = case XData of
                 false ->
                     AllEls;
                 _ ->
                     lists:delete(XData, AllEls)
             end,

    #adhoc_request{lang = Lang,
                   node = Node,
                   sessionid = SessionID,
                   action = Action,
                   xdata = XData,
                   others = Others};
parse_request(_) ->
    {error, ?ERR_BAD_REQUEST}.

%% @doc Borrowed from mod_vcard.erl
-spec find_xdata_el(jlib:xmlel()) -> false | jlib:xmlel().
find_xdata_el(#xmlel{children = SubEls}) ->
    find_xdata_el1(SubEls).

%% @private
find_xdata_el1([]) ->
    false;
find_xdata_el1([XE = #xmlel{attrs = Attrs} | Els]) ->
    case xml:get_attr_s(<<"xmlns">>, Attrs) of
        ?NS_XDATA ->
            XE;
        _ ->
            find_xdata_el1(Els)
    end;
find_xdata_el1([_ | Els]) ->
    find_xdata_el1(Els).

%% @doc Produce a <command/> node to use as response from an adhoc_response
%% record, filling in values for language, node and session id from
%% the request.
-spec produce_response(request(), response()) -> response().
produce_response(#adhoc_request{lang = Lang,
                                node = Node,
                                sessionid = SessionID},
                 Response) ->
    produce_response(Response#adhoc_response{lang = Lang,
                                             node = Node,
                                             sessionid = SessionID}).

%% @doc Produce a <command/> node to use as response from an adhoc_response
%% record.
-spec produce_response(response()) -> jlib:xmlel().
produce_response(#adhoc_response{lang = _Lang,
                                 node = Node,
                                 sessionid = ProvidedSessionID,
                                 status = Status,
                                 defaultaction = DefaultAction,
                                 actions = Actions,
                                 notes = Notes,
                                 elements = Elements}) ->
    SessionID = if is_binary(ProvidedSessionID), ProvidedSessionID /= <<"">> ->
                        ProvidedSessionID;
                   true ->
                        jlib:now_to_utc_binary(os:timestamp())
                end,
    case Actions of
        [] ->
            ActionsEls = [];
        _ ->
            case DefaultAction of
                <<"">> ->
                    ActionsElAttrs = [];
                _ ->
                    ActionsElAttrs = [{<<"execute">>, DefaultAction}]
            end,
            ActionsEls = [#xmlel{name = <<"actions">>, attrs = ActionsElAttrs,
                                 children = [#xmlel{name = Action} || Action <- Actions]}]
    end,
    NotesEls = lists:map(fun({Type, Text}) ->
                                 #xmlel{name = <<"note">>,
                                        attrs = [{<<"type">>, Type}],
                                        children = [#xmlcdata{content = Text}]}
                         end, Notes),
    #xmlel{name = <<"command">>,
           attrs = [{<<"xmlns">>, ?NS_COMMANDS},
                    {<<"sessionid">>, SessionID},
                    {<<"node">>, Node},
                    {"status", list_to_binary(atom_to_list(Status))}],
           children = ActionsEls ++ NotesEls ++ Elements}.
