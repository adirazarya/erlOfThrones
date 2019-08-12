% =================================================================================
% Declarations
% =================================================================================
-module(whiteking).
-behaviour(gen_fsm).
-include("MACROS.hrl").

% =================================================================================
% Exports
% =================================================================================
-export([init/1]).
-export([waiting/2]).
-export([handle_event/3]).
-export([handle_sync_event/4]).
-export([handle_info/3]).
-export([terminate/3]).
-export([code_change/4]).
-export([start_link/3]).
-export([eaten/1]).
-export([changepos/3]).
-export([kill/1]).

% =================================================================================
% WHITEKING CONTROL UNIT
% =================================================================================
start_link(theKnightKing, ServerName, Position) -> gen_fsm:start(?MODULE, [theKnightKing, ServerName, Position], []).
eaten(theKnightKing) -> gen_fsm:send_event({global,theKnightKing}, eaten).
changepos(theKnightKing,_Pos,_ServerName) -> gen_fsm:send_event({global,theKnightKing}, {changepos, _Pos,_ServerName}).
%whitewalker(theKnightKing) -> gen_fsm:send_event({global,theKnightKing}, whitewalker).
kill(theKnightKing) -> gen_fsm:send_event({global,theKnightKing}, kill).

% =================================================================================
% functions implementation
% =================================================================================
% ===== Module: init/1 =====
init([theKnightKing, ServerName, Position]) ->
	Self = self(),
	spawn(fun() -> global:register_name(theKnightKing,Self) end),
	put(id, theKnightKing),
	put(server, ServerName),
	put(position, 		Position),
	process_flag(trap_exit, true),
	io:fwrite("whiteking id:~p~n" ,[Self]),
	startTimeout(),
	% initial whiteking state is waiting.
	{ok, waiting, {}}.
	
% ===== Module: state_name/2 =====
% Whiteking have been eaten.
waiting(eaten, StateData) ->
	cancelEventTimer(),
	io:fwrite("the knight king is dead!!!!~n"),
	square_server:delete(get(server), get(id), kill),
	%exit(self(), eaten),
    {stop, eaten, StateData};

% Whiteking Decay.
waiting(whitewalker, StateData) ->
	cancelEventTimer(),
	%square_server:addWhitewalker(get(server), Ref = erlang:list_to_atom(erlang:ref_to_list(make_ref())),get(position), get(position),?WHITEWALKER_TIMEOUT_FOOD,false,get(id)), 
	io:fwrite("whiteking id:~p~n" , [self()]),
	spawn_link(square_server, addWhitewalker,[get(server),  erlang:list_to_atom(erlang:ref_to_list(make_ref())),get(position), get(position),?WHITEWALKER_TIMEOUT_FOOD,false,get(id)]), %Ref =%

	%square_server:delete(get(server), get(id), kill),
	startTimeout(),
	{next_state,waiting , StateData};
    %{stop, normal, StateData}.
	
waiting({changepos,_Pos,_ServerName}, StateData) ->
	put(server, _ServerName),
	put(position, 		_Pos),
	{next_state,waiting , StateData};
	
waiting(kill, StateData) ->
	cancelEventTimer(),
	io:fwrite("the knight king is killed!!!!~n"),
	square_server:delete(get(server), get(id), kill),
	{stop, normal, StateData}.
%					~~~~~~~~~~~~~~~~~~~~~~~ startTimeout ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% send kill event after WHITEKING_TIMEOUT, if the whiteking wasn't eaten till WHITEKING_TIMEOUT
startTimeout() -> Event = gen_fsm:send_event_after(?WHITEKING_TIMEOUT, whitewalker), put(wwTimout, Event).

%					~~~~~~~~~~~~~~~~~~~~~~~~ cancelEventTimer ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
cancelEventTimer() -> Event = get(wwTimout), gen_fsm:cancel_timer(Event).
	
% ===== Module: handle_event/3 =====
handle_event(_Event, StateName, StateData) -> 
			{next_state, StateName, StateData}.
	
% ===== Module: handle_sync_event/4 =====
handle_sync_event(_Event, _From, StateName, StateData) -> Reply = ok, {reply, Reply, StateName, StateData}.

% ===== Module: handle_info/3 =====
handle_info(_Info, StateName, StateData) -> {next_state, StateName, StateData}.

% ===== Module: terminate/3 =====
terminate(_Reason, _StateName, _StatData) -> ok.

% ===== Module: code_change/4 =====
code_change(_OldVsn, StateName, StateData, _Extra) -> {ok, StateName, StateData}.
