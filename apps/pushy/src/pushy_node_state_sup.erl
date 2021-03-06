%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
%% ex: ts=4 sw=4 et

%% @copyright Copyright 2011-2012 Chef Software, Inc. All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License. You may obtain
%% a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied. See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
-module(pushy_node_state_sup).

-behaviour(supervisor).

-include_lib("pushy.hrl").
-include_lib("pushy_sql.hrl").

% This isn't actually used right now; if the lager call is uncommented, this needs
% to be uncommented instead.
%-compile([{parse_transform, lager_transform}]).

%% API
-export([start_link/0,
         get_or_create_process/3,
         get_process/1,
         get_heartbeating_nodes/0,
         get_heartbeating_nodes/1,
         mk_gproc_name/1,
         mk_gproc_addr/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%% TODO: not clear yet what we should use in place of 'any()' here
-type heartbeating_node() :: {node_ref(), any()}.

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    case supervisor:start_link({local, ?SERVER}, ?MODULE, []) of
        {ok, Pid} ->
            {ok, Pid};
        Error ->
            Error
    end.

-spec get_or_create_process(node_ref(), node_addr(), binary()) -> pid().
get_or_create_process(NodeRef, NodeAddr, IncarnationId) ->
    GprocName = mk_gproc_name(NodeRef),
    case catch gproc:lookup_pid({n,l,GprocName}) of
        {'EXIT', _} ->
            % Run start_child asynchronously; we only need to wait until the
            % process registers itself before we can send it messages.
            spawn(supervisor, start_child, [?SERVER, [NodeRef, NodeAddr, IncarnationId]]),
            {Pid, _Value} = gproc:await({n,l,GprocName},infinity),
            Pid;
        Pid -> Pid
    end.

-spec get_process(node_ref() | binary()) -> pid() | undefined.
get_process({_,_} =NodeRef) ->
    GprocName = mk_gproc_name(NodeRef),
    get_process_int(GprocName);
get_process(Addr) when is_binary(Addr) ->
    GprocName = mk_gproc_addr(Addr),
    get_process_int(GprocName).

-spec get_process_int({heartbeat, org_id(), node_name()} |
                      {addr, binary()}) -> pid() | undefined.
get_process_int(GprocName) ->
    case catch gproc:lookup_pid({n,l,GprocName}) of
        {'EXIT', _} ->
            undefined;
        Pid -> Pid
    end.

-spec get_heartbeating_nodes() -> list(heartbeating_node()).
get_heartbeating_nodes() ->
    do_get_heartbeating_nodes({heartbeat, '_', '_'}).

-spec get_heartbeating_nodes(org_id()) -> list(heartbeating_node()).
get_heartbeating_nodes(OrgId) when is_binary(OrgId) ->
    do_get_heartbeating_nodes({heartbeat, OrgId, '_'}).

-spec mk_gproc_name(node_ref()) -> {'heartbeat', org_id(), node_name()}.
mk_gproc_name({OrgId, NodeName}) when is_binary(OrgId) andalso is_binary(NodeName) ->
    {heartbeat, OrgId, NodeName}.

-spec mk_gproc_addr(binary()) -> {'addr', binary()}.
mk_gproc_addr(Addr) when is_binary(Addr) ->
    {addr, Addr}.

%% ------------------------------------------------------------------
%% supervisor Function Definitions
%% ------------------------------------------------------------------

init([]) ->
    %If this call is uncommented, uncomment compile at top of file, too:
    %lager:trace_console([{module, pushy_node_state}], debug),
    {ok, {{simple_one_for_one, 60, 120},
          [{pushy_node_state, {pushy_node_state, start_link, []},
            transient, brutal_kill, worker, [pushy_node_state]}]}}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% TODO: don't take 'heartbeat' as part of the input of this function; it's an
%% implementation detail
-spec do_get_heartbeating_nodes(GProcName :: {heartbeat,
                                              '_' | org_id(),
                                              '_' | node_name()}) ->
                                        [heartbeating_node()].
do_get_heartbeating_nodes(GProcName) ->
    GProcKey = {n, l, GProcName},
    Pid = '_',
    Value = '_',
    MatchSpec = [{{GProcKey, Pid, Value}, [], ['$$']}],

    Nodes = gproc:select(MatchSpec),
    [{{Org, NodeName}, Val} || [{_,_,{_, Org, NodeName}},_,Val] <- Nodes].

