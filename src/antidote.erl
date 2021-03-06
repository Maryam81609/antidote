%% -------------------------------------------------------------------
%%
%% Copyright (c) 2014 SyncFree Consortium.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%%@doc This file is the public api of antidote

-module(antidote).

-include("antidote.hrl").

%% API for applications
-export([ start/0, stop/0,
          start_transaction/2,
          read_objects/2,
          read_objects/3,
          update_objects/2,
          update_objects/3,
          abort_transaction/1,
          commit_transaction/1,
          create_bucket/2,
          create_object/3,
          delete_object/1,
          register_pre_hook/3,
          register_post_hook/3,
          unregister_hook/2
        ]).


%% Public API

-spec start() -> {ok, _} | {error, term()}.
start() ->
    application:ensure_all_started(antidote).

-spec stop() -> ok.
stop() ->
    application:stop(antidote).

%% Object creation and types
create_bucket(_Bucket, _Type) ->
    %% TODO: Bucket is not currently supported
    {error, operation_not_supported}.

create_object(_Key, _Type, _Bucket) ->
    %% TODO: Object creation is not currently supported
    {error, operation_not_supported}.

delete_object({_Key, _Type, _Bucket}) ->
    %% TODO: Object deletion is not currently supported
    {error, operation_not_supported}.

%% Register a post commit hook.
%% Module:Function({Key, Type, Op}) will be executed after successfull commit of
%% each transaction that updates Key.
-spec register_post_hook(bucket(), module_name(), function_name()) -> ok | {error, function_not_exported}.
register_post_hook(Bucket, Module, Function) ->
    antidote_hooks:register_post_hook(Bucket, Module, Function).

%% Register a pre commit hook.
%% Module:Function({Key, Type, Op}) will be executed before executing an update "op"
%% on key. If pre commit hook fails, transaction will be aborted
-spec register_pre_hook(bucket(), module_name(), function_name()) -> ok | {error, function_not_exported}.
register_pre_hook(Bucket, Module, Function) ->
    antidote_hooks:register_pre_hook(Bucket, Module, Function).

-spec unregister_hook(pre_commit | post_commit, bucket()) -> ok.
unregister_hook(Prefix, Bucket) ->
    antidote_hooks:unregister_hook(Prefix, Bucket).

%% Transaction API %%
%% ==============  %%

-spec start_transaction(Clock::snapshot_time(), Properties::txn_properties())
                       -> {ok, txid()} | {error, reason()}.
start_transaction(Clock, Properties) ->
    cure:start_transaction(Clock, Properties, false).

-spec abort_transaction(TxId::txid()) -> {error, reason()}.
abort_transaction(TxId) ->
    cure:abort_transaction(TxId).

-spec commit_transaction(TxId::txid()) ->
                                {ok, snapshot_time()} | {error, reason()}.
commit_transaction(TxId) ->
    cure:commit_transaction(TxId).
%% TODO: Execute post_commit hooks here?

-spec read_objects(Objects::[bound_object()], TxId::txid())
                  -> {ok, [term()]} | {error, reason()}.
read_objects(Objects, TxId) ->
    cure:read_objects(Objects, TxId).

-spec update_objects([{bound_object(), op_name(), op_param()} | {bound_object(), {op_name(), op_param()}}], txid())
                    -> ok | {error, reason()}.
update_objects(Updates, TxId) ->
    case type_check(Updates) of
        ok ->
            cure:update_objects(Updates, TxId);
        {error, Reason} ->
            {error, Reason}
    end.

%% For static transactions: bulk updates and bulk reads
-spec update_objects(snapshot_time() | ignore , list(), [{bound_object(), op_name(), op_param()}| {bound_object(), {op_name(), op_param()}}]) ->
                            {ok, snapshot_time()} | {error, reason()}.
update_objects(Clock, Properties, Updates) ->
    case type_check(Updates) of
        ok ->
            cure:update_objects(Clock, Properties, Updates);
        {error, Reason} ->
            {error, Reason}
    end.

-spec read_objects(vectorclock(), any(), [bound_object()]) ->
                          {ok, list(), vectorclock()} | {error, reason()}.
read_objects(Clock, Properties, Objects) ->
    cure:read_objects(Clock, Properties, Objects).

%%% Internal function %%
%%% ================= %%

type_check_update({{_K, Type, _bucket}, Op, Param}) ->
    antidote_crdt:is_type(Type) andalso
        Type:is_operation({Op, Param}).

-spec type_check([{bound_object(), op_name(), op_param()}]) -> ok | {error, reason()}.
type_check(Updates) ->
    try
        lists:foreach(fun(Update) ->
                              case type_check_update(Update) of
                                  true -> ok;
                                  false -> throw({badtype, Update})
                              end
                      end, Updates),
        ok
    catch
        _:Reason ->
            {error, Reason}
    end.
