%%%-------------------------------------------------------------------
%%% @author Kai Janson <kai.janson@MHM23TDV13>
%%% @copyright (C) 2012, Kai Janson
%%% @doc
%%%
%%% @end
%%% Created :  1 Jul 2012 by Kai Janson <kai.janson@MHM23TDV13>
%%%-------------------------------------------------------------------
-module(cloudfiles).

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {cdn, storage, token}).

%% For create()
-include_lib("kernel/include/file.hrl").

%% Functions for the Cloudfiles API
-export([authenticate/0]).
-export([create_container/1]).
-export([list/1]).
-export([delete/1]).
-export([create/2]).
%% Additional functions
-export([dump/0]).
-export([fire/0]).

%%%===================================================================
%%% API
%%%===================================================================
authenticate() ->
    gen_server:call(?MODULE, authenticate).

create_container(Name) ->
    gen_server:call(?MODULE, {create_container, Name}).

list(Container) ->
    gen_server:call(?MODULE, {list, Container}).

delete(Container) ->
    gen_server:call(?MODULE, {delete, Container}).

create(Container, Filename) ->
    gen_server:call(?MODULE, {create, Container, Filename}).

%% Additional functions
dump() ->
    gen_server:call(?MODULE, dump).
fire() ->
    gen_server:call(?MODULE, fire).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({create, Container, Filename}, _From, State) ->
    Filesize = case file:read_file_info(Filename) of
		   {ok, FileInfo} ->
		       FileInfo#file_info.size;
		   {error, Reason} ->
		       Reason
	       end,
    Location = case Container of
		   [] ->
		       lists:flatten(io_lib:format("~s/~s", [State#state.storage, filename:basename(Filename)]));
		   Folder ->
		       lists:flatten(io_lib:format("~s/~s/~s", [State#state.storage, Folder, filename:basename(Filename)]))
	       end,
    Md5 = lists:flatten(tl(string:tokens(string:strip(os:cmd("openssl dgst -md5 " ++ Filename), right, $\n),"= "))),
    error_logger:info_msg("File: ~p~nSize: ~p~nLoca: ~p~nMd5 : ~p~n", [Filename,Filesize,Location,Md5]),
    {ok,{{_Http, Status, _Message},_Headers,_Body}} = httpc:request(put,
                                      {Location,
                                       [
                                        {"X-Auth-Token", State#state.token },
					{"Content-Length", Filesize},
					{"Content-Type", mime_lib:mimetype(filename:extension(Filename))},
					{"ETag", Md5}
                                       ],
                                       mime_lib:mimetype(filename:extension(Filename)), ""
                                      }, [],[{stream, Filename}]),
    Reply = case Status of
		201 ->
		    %% Created, all is good
		    ok;
		400 ->
		    %% Bad Request: The request cannot be fulfilled due to bad syntax.
		    {error, 400, bad_request};
		401 ->
		    %% Unauthorized: Returned upon authentication failure
		    {error, 401, unauthorized};
		403 ->
		    %% Forbidden: The request was a legal request, but the server is refusing to respond to it
		    {error, 403, forbidden};
		411 ->
		    %% Length required: denotes a missing Content-Length or Content-Type header in the request
		    {error, 411, length_required};
		412 ->
		    %% Precondition failed: The server does not meet one of the preconditions that the requester put on the request
		    {error, 412, precondition_failed};
		413 ->
		    %% Request Entity Too Large: The request is larger than the server is willing or able to process
		    {error, 413, request_entity_to_large};
		417 ->
		    %% Expectation Failed: The server cannot meet the requirements of the Expect request-header field
		    {error, 417, expectation_failed};
		422 ->
		    %% Unprocessable entity: indicates that the MD5 checksum of the data written to the
		    %% storage system does NOT match the (optionally) supplied ETag value
		    {error, 422, unprocessable_entity};
		AnythingElse ->
		    {error, AnythingElse, unknown_error}
	    end,
    {reply, Reply, State};
handle_call({delete, Container}, _From, State) ->
    Location = case Container of
		   [] ->
		       lists:flatten(io_lib:format("~s", [State#state.storage]));
		   Folder ->
		       lists:flatten(io_lib:format("~s/~s", [State#state.storage, Folder]))
	       end,
    {ok, {{_Http,Status,_Message},_Headers, _Body}} = httpc:request(delete,
								{ Location,
								  [
								   {"X-Auth-Token", State#state.token}
								  ]
								}, [], []),
    %% Was it successful?
    Reply = case Status of
		204 ->
		    ok;
		404 ->
		    {error, not_found};
		409 ->
		    {error, container_not_empty}
	    end,
    {reply, Reply, Status};
handle_call({list, Container}, _From, State) ->
    SL = case Container of
             [] ->
                 lists:flatten(io_lib:format("~s?format=json", [State#state.storage]));
             Container ->
                 lists:flatten(io_lib:format("~s/~s?format=json", [State#state.storage, Container]))
         end,
    {ok,{{_Http, Status, _Message}, _Headers, Body}} = httpc:request(get,
								     {SL,
								      [
								       {"X-Auth-Token", State#state.token}
								      ]
								     }, [], []),
    Reply = case Status of 404 -> {error, not_found}; _Else -> Body end,
    {reply, Reply, State};
handle_call(fire, _From, State) ->
    application:start(crypto),
    application:start(public_key),
    application:start(ssl),
    application:start(inets),
    Reply = ok,
    {reply, Reply, State};
handle_call(dump, _From, State) ->
    error_logger:info_msg("State: ~p~n", [State]),
    {reply, ok, State};
handle_call(authenticate, _From, State) ->
    {ok, {_Result, Headers, _Body}} = httpc:request(get,
					     {rs_cf_url(),
					      [
                                               {"X-Auth-Key", rs_cf_key()},
					       {"X-Auth-User", rs_cf_user()}
                                              ]
                                             }, [], []),
    Storage = proplists:get_value("x-storage-url", Headers),
    CDNStorage = proplists:get_value("x-cdn-management-url", Headers),
    Token = proplists:get_value("x-storage-token", Headers),
    NewState = State#state{token=Token, cdn=CDNStorage, storage=Storage},
    Reply = ok,
    {reply, Reply, NewState};
handle_call({create_container, Name}, _From, State) ->
    {ok,{{_Http, _Status, Message},_Headers,_Body}} = httpc:request(put,
                                      {State#state.storage ++ "/" ++ Name,
                                       [
                                        {"X-Auth-Token", State#state.token }
                                       ],
                                       "text/xml", ""
                                      }, [],[]),
    %% Was it successful?
    Reply = case Message of "Created" -> true; _Else -> false end,
    {reply, Reply, State}.

%%handle_call(_Request, _From, State) ->
%%    Reply = ok,
%%    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
rs_cf_key() ->
    "63ae7709f54b149ca3e00e8628ef9dae".

%% Returns the Rackspace Cloud File Username.                                                                                                                
rs_cf_user() ->
    "samuelrose".

%% Returns the Rackspace Cloud File URL.                                                                                                                     
rs_cf_url() ->
    "https://auth.api.rackspacecloud.com/v1.0".

