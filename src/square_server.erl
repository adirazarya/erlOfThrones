% =================================================================================
% Declarations
% =================================================================================
-module(square_server).
-behaviour(gen_server).
-include_lib("stdlib/include/qlc.hrl").
-include("MACROS.hrl").

% =================================================================================
% Exports
% =================================================================================
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).
-export([start/1]).
-export([stop/1]).
-export([addKnight/6]).
-export([addDragon/6]).
-export([addWhitewalker/7]).
-export([addWhiteking/3]).
-export([delete/3]).
-export([whitekingEaten/2]).
-export([checkRadsAndUpdate/5]).
-export([knightTest/3]).
-export([dragonTest/3]).
-export([whitewalkerTest/3]).
-export([changeServer/7]).
-export([serverReceiveLoop1/2]).
-export([crush/2]).
-export([updateNodesETS/3]).
-export([removeBackup/1]).

% =================================================================================
% Screen server state saved as a record
% =================================================================================
-record(state, { serverName, curr, remove, wx, monitor }).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% ___ETS entry format___:
%% Knight : {ID, {knight, Pos, State}}
%% Whitewalker : {ID, {whitewalker, Pos, State}}
%% Whiteking : {ID, {whiteking, Pos, ?WHITEKINGS_AMOUNT}}
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% =================================================================================
% SERVER CONTROL UNIT
% =================================================================================
start(_srvrName) ->
	group_leader(whereis(user),self()),  	
	Monitor = spawn(fun() -> serverReceiveLoop(_srvrName,[]) end),
	try gen_server:start_link({global, _srvrName}, ?MODULE, [_srvrName,Monitor], []) of
		{'error',_Reason} -> wx_server:removeConnectionStatus(_srvrName, global:whereis_name(wx_server));	 % Receives {error, already_started} when server is up
		_ok -> ok 		 	
	catch 
		error:_ANY -> ok
	end,
	io:fwrite(" *** SERVER ~p IS ON :)***~n",[_srvrName]).

stop(_srvrName) -> spawn(fun() -> gen_server:stop(global:whereis_name(_srvrName),shutdown,infinity) end).
delete(_srvrName, ID, Reason) -> gen_server:cast({global, _srvrName}, {delete, ID, Reason}).
whitekingEaten(_srvrName, POS) -> gen_server:cast({global, _srvrName}, {whitekingEaten, POS}).
checkRadsAndUpdate(_srvrName, ID, Type, POS, ElemState) -> gen_server:cast({global, _srvrName}, {checkRadsAndUpdate, ID, Type, POS, ElemState}).
changeServer(_srvrName, ID, POS, Dest, FoodRT, StuffedRT,KingID) -> gen_server:cast({global, _srvrName}, {changeServer, ID, POS, Dest, FoodRT, StuffedRT,KingID}).
crush(_srvrName, Reason) -> gen_server:cast({global, _srvrName}, {crush, Reason}).
serverReceiveLoop1(_srvrName, List) -> gen_server:cast({global, _srvrName}, {serverReceiveLoop1, List}).
removeBackup(_srvrName)-> gen_server:cast({global, _srvrName}, {removeBack,_srvrName}).
%updateNodesETS(undefined,Heir,Server)->ok;
updateNodesETS(_srvrName,Heir,Server) -> gen_server:cast({global, _srvrName}, {updateNodesETS, Heir,Server}).

% =================================================================================
% ADD ELEMENTS
% =================================================================================
% -------- add elements using cast call, Send an asynchronous request " addKnight/addWhitewalker/addWhiteking" to the "ServerName" Server --------
addKnight(_srvrName, ID, POS, Dest, FoodRT, StuffedRT) -> gen_server:cast({global, _srvrName}, {addKnight, ID, POS, Dest, FoodRT, StuffedRT}).
addDragon(_srvrName, ID, POS, Dest, FoodRT, StuffedRT) -> gen_server:cast({global, _srvrName}, {addDragon, ID, POS, Dest, FoodRT, StuffedRT}).
addWhitewalker(_srvrName, ID, POS, Dest, FoodRT, StuffedRT,KingID) -> gen_server:cast({global, _srvrName}, {addWhitewalker, ID, POS, Dest, FoodRT, StuffedRT,KingID}).
addWhiteking(_srvrName, theKnightKing, POS) -> gen_server:cast({global, _srvrName}, {addWhiteking, theKnightKing, POS, _srvrName}).

% =================================================================================
% ELEMENTS INSPECTIONS
% =================================================================================
% -------- Check radiuses for knight and whitewalkers from the server using cast call --------
knightTest(_srvrName ,ID, POS) -> gen_server:cast({global, _srvrName}, {knightTest, ID, POS}).
dragonTest(_srvrName ,ID, POS) -> gen_server:cast({global, _srvrName}, {dragonTest, ID, POS}).
whitewalkerTest(_srvrName, ID, POS) -> gen_server:cast({global, _srvrName}, {whitewalkerTest, ID, POS}).




% ===== Module: init =====
%% 			Module:init/1 : init a new Server and create a unidirectional relationship with its own MONITOR .
%% 			every server contains 2 ETS tables: 1. Current elemnts  2. Deleted elements.
%%			the server send request in order to update the WX screen every UPDATE_SCREEN time.
init([_srvrName,Monitor]) ->

	Self = self(),												% server ID
	global:register_name(_srvrName,Self),
	io:fwrite("Server Name: ~p~n",[_srvrName]),
	io:fwrite("ID: ~p~n",[Self]),
	io:fwrite("Monitor: ~p~n",[Monitor]),
	Monitor ! {monitor,Self}, 									% Create a connection between Monitor Procees and The server.
	
	CurrETS = ets:new(currETS, [set, public, named_table]),		% table type = set(default table type).
																% access rights = public(aby process can read/write to the table.
																% named_table = access this table by it's name, and return the table name instead of ID.
																
	RemoveETS = ets:new(removeETS, [set]),
	
	% ETS table of nodes
  ets:new(squareNodesNames,   [set,public,named_table]),
  ets:insert(squareNodesNames,{lu,?LU}),
  ets:insert(squareNodesNames,{ld,?LD}),
  ets:insert(squareNodesNames,{ru,?RU}),
  ets:insert(squareNodesNames,{rd,?RD}),
	
	put(serverName, _srvrName),
	
	waitForWx(),
	 
	State = #state{ serverName = _srvrName,						% Init the server state
					curr = CurrETS,
					remove = RemoveETS,
					wx = global:whereis_name(wx_server),
					monitor = Monitor},
	
	erlang:send_after(?UPDATE_SCREEN, self(), updateWxServer),	% Start a new timer
	{ok, State}.

%% waitForWx/0
waitForWx() ->
	case global:whereis_name(wx_server) of
		undefined -> waitForWx();
		_PID      -> ok
	end.

serverReceiveLoop(_srvrName,AddList) ->
	receive
		{monitor,Pid} -> io:fwrite("Monitoring: ~p~n",[Pid]),
						 wx_server:removeConnectionStatus(_srvrName, global:whereis_name(wx_server)),
						 erlang:monitor(process, Pid),
						 serverReceiveLoop(_srvrName,AddList);

		{add,List}	  -> wx_server:removeQuarter(_srvrName, global:whereis_name(wx_server)),
						 serverReceiveLoop(_srvrName,List);
		
		kill 		  -> io:fwrite("Monitor Terminating ~n");
		
		{recover,List}-> %io:fwrite("!!! SHELL CRUSHS !!! ~p~n", [List]), % print and dies
						 wx_server:removeQuarter(_srvrName, global:whereis_name(wx_server)),
						 io:fwrite("Monitor: Restarting Server1... ~n"),
							 %square_server:start(_srvrName),
							 %lists:foreach(fun({ID,{Type, POS,_StateNum}})->
							 lists:foreach(fun({ID,Tup})->
								case element(1,Tup) of
								knight  -> addKnight(_srvrName, erlang:list_to_atom(erlang:ref_to_list(make_ref())), element(2,Tup), element(2,Tup), ?KNIGHT_TIMEOUT_FOOD, false);
								dragon  -> addDragon(_srvrName, erlang:list_to_atom(erlang:ref_to_list(make_ref())), element(2,Tup), element(2,Tup), ?DRAGON_TIMEOUT_FOOD, false);
								whitewalker  -> addWhitewalker(_srvrName, erlang:list_to_atom(erlang:ref_to_list(make_ref())), element(2,Tup), element(2,Tup), ?WHITEWALKER_TIMEOUT_FOOD, false,theKnightKing);
									whiteking -> addWhiteking(_srvrName, ID, element(2,Tup)),
											 wx_server:addWhiteking(ID, element(2,Tup), global:whereis_name(wx_server))
							  end
							  end,List),
							serverReceiveLoop(_srvrName,AddList);
		{removeBack, List}-> io:fwrite("remove back ~p~n", [qlc:eval(List)]),

												 lists:foreach(fun({ID,Tup})->
												 case element(1,Tup) of
												 knight  -> knight:kill(ID);
												 dragon  -> dragon:kill(ID);
												 whitewalker  -> whitewalker:kill(ID);
												 whiteking -> whiteking:kill(ID)
													end
												end,qlc:eval(List)),
	serverReceiveLoop(_srvrName,[]);
							
		ANY 		  -> io:fwrite("!!! SHELL CRUSHS !!! ~p~n", [ANY]), % print and dies
						 wx_server:removeQuarter(_srvrName, global:whereis_name(wx_server)),
						 io:fwrite("Monitor: Restarting Server2... ~n"),
							 square_server:start(_srvrName),
							 %lists:foreach(fun({ID,{Type, POS,_StateNum}})->
							 lists:foreach(fun({ID,Tup})->
								io:fwrite("ANY ~p~p~n", [Tup, ID]),
								case element(1,Tup) of
								knight  -> addKnight(_srvrName, ID, element(2,Tup), element(2,Tup), ?KNIGHT_TIMEOUT_FOOD, false);
								dragon  -> addDragon(_srvrName, ID, element(2,Tup), element(2,Tup), ?DRAGON_TIMEOUT_FOOD, false);
								whitewalker  -> addWhitewalker(_srvrName, ID, element(2,Tup), element(2,Tup), ?WHITEWALKER_TIMEOUT_FOOD, false,theKnightKing);
									whiteking -> addWhiteking(_srvrName, ID, element(2,Tup)),
											 wx_server:addWhiteking(ID, element(2,Tup), global:whereis_name(wx_server))
							end										end,AddList)
		end.
								
%	===== Module: handle_call =====
%% Module:handle_call/3 : Whenever a gen_server process recieves a request sent using call/2,3, this function is called to handle the request.
%%				   Parameters:	
%%								1. Request: request argument provided to call.
%%								2. From:  	a tuple {Pid, Tag}, where Pid is the pid of the client and Tag is a unique tag.
%%								3. State: 	internal state of the gen_server process.
handle_call(_Msg, _From, State) ->
    {reply, State}.
	
%	===== Module: handle_cast =====
%% Module:handle_cast/2 : Whenever a gen_server process recieves a request sent using cast/2, this function is called to handle the request.
%%				   		  Parameters:	
%%								1. Request: request argument provided to call.							
%%								2. State: 	internal state of the gen_server process.

% -------- Handle_cast of server control unit --------
%% Delete Element from the server ETS.
%% Parameters:
%%			1. delete : cast operation.
%%			2. ID : ID item to delete.
%%			3. Reason: The item was eaten/move to another square.
handle_cast({delete, ID, Reason}, State) ->
	case Reason of
		kill   -> ets:insert(State#state.remove,{ID,delete});
		delete -> ok
	end,
	ets:delete(State#state.curr, ID),                           % Delete element.
	{noreply, State};

%% Knight/Dragon acknowledges its server when it eats a whiteking, using its position as identifier.
handle_cast({whitekingEaten, {CX,CY}=POS}, State) ->
	case outOfSquare(POS) of
		false ->												% Whiteking in the current square.
			Tab = qlc:q([{_ID,{whiteking,{X,Y},Count}} || {_ID,{whiteking,{X,Y},Count}} <- ets:table(State#state.curr),
									(CX == X) and (CY == Y) ]),
			case qlc:eval(Tab) of
				[] ->  											% No whitekings in the current square in Knight radius 
					false;
				[{WhitekingID,{_Type,_Pos,Count}}|_Others] ->
					case  Count-1 =< 0 of
						true ->   								% Delete whiteking.
							whiteking:eaten(WhitekingID),
							ets:insert(State#state.remove,{WhitekingID,delete}),
							ets:delete(State#state.curr, WhitekingID);
						false ->  								% Decrement Count in 1
							ets:insert(State#state.curr, {WhitekingID,{whiteking, _Pos, Count-1}})
					end
			end;
		true ->													% Whiteking in the near square.
			SrvName = getServer(POS),
			square_server:whitekingEaten(SrvName, POS)
	end,	
	{noreply, State};

%% 1. For every new position (X,Y) server "check radiuses" for the relevant element(Knight/Whitewalker).
%% 2. The server check for the elements the relevant radiuses.
%% 3. The server generates suitable events according to whitewalker/knight radiuses test.
%% Parameters:
%%			1. ID: element id.
%%			2. Type: element type.
%%			3. POS: the element new position (X,Y).
%%			4. ElemState: state of the element.
%%			5. State: The Server state.

handle_cast({checkRadsAndUpdate, ID, Type, POS, ElemState}, State) ->
	case Type of 															% Scan the local server area with the relevant radiuses.
		knight ->
			checkRadF(ID, POS, State#state.curr, local);
		dragon ->
			checkRadD(ID, POS, State#state.curr, local);
		whitewalker ->
			checkRadS(ID, POS, State#state.curr, local)
	end,
    case ets:lookup(State#state.curr, ID) of								% Update the new position and state.
		[] -> ignore;
		_Element-> 															
			ets:insert(State#state.curr, {ID, {Type, POS, ElemState}})
	end,			
	{noreply, State};
	
%% check radiuses for knight "not local test" (the current server is not the local one).
handle_cast({knightTest, Pos, ID}, State) ->
	checkRadF(ID, Pos, State#state.curr, notLocal),
    {noreply, State};
	
handle_cast({dragonTest, Pos, ID}, State) ->
	checkRadD(ID, Pos, State#state.curr, notLocal),
    {noreply, State};
	
%% check radiuses for whitewalker.
handle_cast({whitewalkerTest,Pos, ID}, State) ->
	checkRadS(ID,Pos, State#state.curr,notLocal),
    {noreply, State};
	
%% change nodes ets.
handle_cast({updateNodesETS,Heir,Server}, State) ->
	ets:insert(squareNodesNames,{Server,Heir}),
	io:fwrite("updateNodesETS: Server:~p, Heir: ~p ~n", [Server,Heir]),
	io:fwrite("resukrt is:~p ~n", [ets:lookup_element(squareNodesNames,Server,2)]),
	{noreply, State};
	
%% Deliver ElementID to other square in remote node.
handle_cast({changeServer, ID, POS, Dest, FoodRT, StuffedRT,KingID}, State) ->
	Serv = getServer(POS),
	move2another(Serv, ID, POS, Dest, FoodRT, StuffedRT, State#state.curr,KingID),
	{noreply, State};
	
%% Server Crush handle:
%% 			case 1- Shut down: terminates server and it's elements.
%%			case 2- Normak crush: Force crush by dividing by 0.
%%			case 3- Restart: kill the server elements and restart it.
%% CASE 1		
handle_cast({crush,shutdown}, State) ->							
		io:fwrite("Shutting Down crush:~n"),
    {stop,shutdown, State};
%% CASE 2
handle_cast({crush,normal}, State) ->
 		%1/0,
		io:fwrite("Shutting Down normal:~n"),
    {stop, normal, State};

handle_cast({crush,restart}, State) ->	
	 	deleteObjects(),
	 	ets:delete_all_objects(currETS),
    {stop, normal, State};
	


% -------- Handle_cast of adding new elements : Knight, Whitewalker and Whitekings --------

%% Add Knight handle cast:
%%				1. Create Knight gen_fsm.
%%				2. Add entry to server ETS.
%%				3. Knight default state is "walking".
handle_cast({addKnight, ID, Pos, Dest, FoodRT, StuffedRT}, State) ->
	knight:start_link(ID, Pos, Dest, FoodRT,StuffedRT,State#state.serverName),
	ets:insert(State#state.curr,{ID, {knight, Pos, walking}}),
	{noreply, State};
	
%% Add Dragon handle cast:
%%				1. Create Dragon gen_fsm.
%%				2. Add entry to server ETS.
%%				3. Dragon default state is "walking".
handle_cast({addDragon, ID, Pos, Dest, FoodRT, StuffedRT}, State) ->
	dragon:start_link(ID, Pos, Dest, FoodRT,StuffedRT,State#state.serverName),
	ets:insert(State#state.curr,{ID, {dragon, Pos, walking}}),
	{noreply, State};

%% Add Whitewalker handle cast:
%%				1. Create whitewalker gen_fsm.
%%				2. Add entry to server ETS.
%%				3. Whitewalker default state is "walking".
handle_cast({addWhitewalker, ID, Pos, Dest, FoodRT, StuffedRT,KingID}, State) ->
	whitewalker:start_link(ID, Pos, Dest, FoodRT,StuffedRT, State#state.serverName,KingID),
	ets:insert(State#state.curr,{ID, {whitewalker, Pos, walking,KingID}}),
	{noreply, State};

%% Add whiteking handle cast:
%%				1. Create whiteking gen_fsm.
%%				2. Add entry to server ETS.
handle_cast({addWhiteking, theKnightKing, Pos,ServerName}, State) ->
	case global:whereis_name(theKnightKing) of
		undefined -> whiteking:start_link(theKnightKing, ServerName, Pos);
								 %wx_server:addWhiteking(theKnightKing, Pos, global:whereis_name(wx_server));
		_Else -> whiteking:changepos(theKnightKing,Pos,ServerName)
						 %whiteking:start_link(theKnightKing, ServerName, Pos),
						 %timer:sleep(1000),
						 %wx_server:addWhiteking(theKnightKing, Pos, global:whereis_name(wx_server))
		%whiteking:start_link(theKnightKing, ServerName, Pos)
		%addWhiteking(ServerName, theKnightKing, Pos),
		%wx_server:addWhiteking(theKnightKing, Pos, global:whereis_name(wx_server))
		
	end,
	ets:insert(State#state.curr, {theKnightKing,{whiteking, Pos, ?WHITEKING_AMOUNT}}),
	{noreply, State};
	
handle_cast({serverReceiveLoop1,List}, State) ->							
		io:fwrite("serverReceiveLoop:~n"),
		State#state.monitor ! {recover,List},
    {noreply, State};

handle_cast({removeBack,_srvrName}, State) ->
	io:fwrite("removeBack:~n"),
	State#state.monitor ! {removeBack,qlc:q([{ID,{Type,{X,Y},_StateName}} || {ID,{Type,{X,Y},_StateName}} <- ets:table(State#state.curr), getServer({X,Y}) /= _srvrName])},
	{noreply, State}.


% ===== Module: handle_info =====
%% The server recieves an update message every ?UPDATE_SCREEN interval time by erlang:send_after method.
%% This server send the wx_server its participants information and deleted participants information.
handle_info(updateWxServer, State) ->
 	FS_TB = qlc:q([{ID,{Type,{X,Y},_StateName}} || {ID,{Type,{X,Y},_StateName}} <- ets:table(State#state.curr)]), %, Type /= whiteking
 	%case qlc:eval(FS_TB) of
 		%wx_server:etsTableUpdate([] ,ets:tab2list(State#state.remove), global:whereis_name(wx_server)), % No Knight/Whitewalker live in this server
 		%ets:delete_all_objects(State#state.remove);
 		%FS_TB ->
			wx_server:etsTableUpdate(qlc:eval(FS_TB),ets:tab2list(State#state.remove),global:whereis_name(wx_server)),
 			ets:delete_all_objects(State#state.remove),			% restart ETS
 	%end,
	erlang:send_after(?UPDATE_SCREEN, self(), updateWxServer),		% Start new timer 
    {noreply, State}.
	

%	===== Module: handle_terminate =====
%% Shutdown - kill monitor and participants FSM.
terminate(shutdown, State) ->
	State#state.monitor ! kill, 
	io:fwrite("Deleting objects...~n"),
 	deleteObjects(),
	io:fwrite("Server Shutdown!~n");

%% Other reason - restart\crush - will kill the server and the monitor will restart it again
terminate(Reason, State) ->
    io:fwrite("Crushed received!~p~n", [Reason]),
    List = ets:tab2list(currETS),
    deleteObjects(),
    State#state.monitor ! {add, List}.	% restart participants.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%------------------------------------------ Elements inspictions implementation - internal functions ------------------------------------------ 
%											~~~~~~~~~~~~~~~~~~~~~~~~~~~checkRadF~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Checks radiuses for knight according to the priority order:
%% 1. Check for whitewalker in radius.
%% 2. Check for whiteking in radius
%% 3. Check for obstacle.
%% Generate suitable event according to the result.
%% Parameters:
%%			1. ID : Knight id.
%%			2. POS: Knight position (X,Y).
%%			3. ETS: Server ETS.
%%			4. ServConfig: check radius for knight in the server/Other server ETS (locaL/notLocal).

checkRadF(ID, POS, ETS, ServConfig) ->


	% Priority 1: RETURN table of whitewalkers in whitewalker_radius.
	Whitewalkers_TB = qlc:q([{X,Y} || {_ID,{whitewalker,{X,Y},_State}} <- ets:table(ETS), distance(POS,{X,Y}) < ?WHITEWALKER_RADIUS ]), 				
	
	case qlc:eval(Whitewalkers_TB) of																								
		[] ->  				% CASE 1:  No whitewalkers in whitewalker_radius at the local server.																												
			case ServConfig of
				local -> 	% Check in the other servers.																										
					servs2Check(ID, knight, POS, ?WHITEWALKER_RADIUS); 
				notLocal -> none
			end,
			
			% Priority 2:  RETURN table of whitekings in radius.					
			Whiteking_TB = qlc:q([{X,Y} || {_ID,{whiteking,{X,Y},_Count}} <- ets:table(ETS), distance(POS,{X,Y}) < ?WHITEKING_RADIUS ]),

			case qlc:eval(Whiteking_TB) of
				[] ->  		% CASE 1: No whitekings in knight radius at local server.
				
					% Priority 3: Search for obstacle.				
					FS_TB = qlc:q([{X,Y} || {_ID,{_Type,{X,Y},_State}} <- ets:table(ETS), (ID /= _ID) and (distance(POS,{X,Y}) < ?MINIMUM_RANGE) ]),
					Whitekings_TB = qlc:q([{X,Y} || {_ID,{whiteking,{X,Y},_Count}} <- ets:table(ETS), distance(POS,{X,Y}) < ?MINIMUM_RANGE ]),

					case qlc:eval(FS_TB) ++ qlc:eval(Whitekings_TB) of
						[] ->  		% No obstacles
							none;
						[Obstcale_XY|_Others] ->
							knight:obstacle(ID, Obstcale_XY)
					end;
				[Whiteking_XY|_Others] ->
					knight:gotoWhiteking(ID, Whiteking_XY)  % GOTO whiteking.
			end;					
		[Whitewalker_XY|_Others] ->
		
			case ServConfig of
				local -> 	% Check in the other servers.																										
					servs2Check(ID, knight, POS, ?WHITEWALKER_RADIUS); 
				notLocal -> none
			end,
						
			Whiteking_TB = qlc:q([{X,Y} || {_ID,{whiteking,{X,Y},_Count}} <- ets:table(ETS), distance(POS,{X,Y}) < ?WHITEKING_RADIUS ]),

			case qlc:eval(Whiteking_TB) of
				[] ->  		
					knight:escape(ID, Whitewalker_XY);
				[Whiteking_XY] ->
					io:fwrite("whiteking_xy:~p~n", [Whiteking_XY]),
					knight:gotoWhiteking(ID, Whiteking_XY);  % GOTO whiteking.
				[Whiteking_XY|_Others] ->
					io:fwrite("whiteking_xy:~p~n", [Whiteking_XY]),
					knight:gotoWhiteking(ID, Whiteking_XY)  % GOTO whiteking.
			end
		
		%	FS_TB = qlc:q([{X,Y} || {_ID,{Type,{X,Y},_State}} <- ets:table(ETS), (_ID /= ID) and (distance(POS,{X,Y}) < ?MINIMUM_RANGE) ]),
		%	Whitekings_TB = qlc:q([{X,Y} || {_ID,{whiteking,{X,Y},Count}} <- ets:table(ETS), distance(POS,{X,Y}) < ?MINIMUM_RANGE ]),
									    
			
		%	case qlc:eval(FS_TB) ++ qlc:eval(Whitekings_TB) of
		%		[] ->  			% No obstacles
		%			none;
		%		[Obstcale_XY|_Other] ->
		%			knight:obstacle(ID, Obstcale_XY)
		%	end,
			
			
	end.
	
	
%														~~~~~~~~~~~~~~~~~~~~~~~~~~~checkRadD~~~~~~~~~~~~~~~~~~~~~~~~~~~~

%% Checks radiuses for dragon according to the priority order:
%% 1. Check for whiteking in radius
%% 2. Check for obstacle.
%% Generate suitable event according to the result.
%% Parameters:
%%			1. ID : Dragon id.
%%			2. POS: Dragon position (X,Y).
%%			3. ETS: Server ETS.
%%			4. ServConfig: check radius for dragon in the server/Other server ETS (locaL/notLocal).

checkRadD(ID, POS, ETS, _ServConfig) ->

			
		% Priority 1:  RETURN table of whitekings in radius.					
		Whiteking_TB = qlc:q([{X,Y} || {_ID,{whiteking,{X,Y},_Count}} <- ets:table(ETS), distance(POS,{X,Y}) < ?WHITEKING_RADIUS ]),

		case qlc:eval(Whiteking_TB) of
			[] ->  		% CASE 1: No whitekings in dragon radius at local server.
			
				% Priority 2: Search for obstacle.				
				FS_TB = qlc:q([{X,Y} || {_ID,{_Type,{X,Y},_State}} <- ets:table(ETS), (ID /= _ID) and (distance(POS,{X,Y}) < ?MINIMUM_RANGE) ]),
				Whitekings_TB = qlc:q([{X,Y} || {_ID,{whiteking,{X,Y},_Count}} <- ets:table(ETS), distance(POS,{X,Y}) < ?MINIMUM_RANGE ]),

				case qlc:eval(FS_TB) ++ qlc:eval(Whitekings_TB) of
					[] ->  		% No obstacles
						none;
					[Obstcale_XY|_Others] ->
						dragon:obstacle(ID, Obstcale_XY)
				end;
				
			[Whiteking_XY|_Others] ->
				dragon:gotoWhiteking(ID, Whiteking_XY)  % GOTO whiteking.
		end.				
		

	
%								~~~~~~~~~~~~~~~~~~~~~~~~~~~checkRadS~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Checks radiuses for whitewalker according to the priority order:
%% 1. Check for knight in radius. 
%% 2. Check for obstacle.
%% Generate suitable event according to the result.
%% Parameters:
%%			1. ID : Whitewalker id.
%%			2. POS: Whitewalker position (X,Y).
%%			3. ETS: Server ETS.
%%			4. ServConfig: check radius for Whitewalker in the server ETS/Other server ETS (locaL/notLocal).

checkRadS(ID, POS, ETS, ServConfig) ->
	Knight_TB = qlc:q([{{X,Y}, _ID} || {_ID,{knight,{X,Y},_State}} <- ets:table(ETS), distance(POS,{X,Y}) < ?KNIGHT_RADIUS ]),
							
	case qlc:eval(Knight_TB) of
		[] ->  			 % No knight in whitewalker radius
			case ServConfig of
				local -> % Check in remote nodes
					servs2Check(ID, whitewalker, POS, ?KNIGHT_RADIUS);
				notLocal -> none
			end,
			Elements_TB = qlc:q([{X,Y} || {_ID,{_Type,{X,Y},_State}} <- ets:table(ETS),(_ID /= ID) and (distance(POS,{X,Y}) < ?MINIMUM_RANGE) ]),
			Whitekings_TB = qlc:q([{X,Y} || {_ID,{whiteking,{X,Y},_Count}} <- ets:table(ETS), distance(POS,{X,Y}) < ?MINIMUM_RANGE ]),
									    
			case qlc:eval(Elements_TB) ++ qlc:eval(Whitekings_TB) of
				[] ->  % No obsticales
					none;
				[Obstcale_XY|_Others] ->
					knight:obstacle(ID, Obstcale_XY)
			end;
		[{Knight_XY, Knight_ID}|_Others] ->
			whitewalker:gotoKnight(ID, Knight_ID, Knight_XY)
	end.

%								~~~~~~~~~~~~~~~~~~~~~~~~~~servs2Check~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Check radius in the next servers by the knight/whitewalker/dragon position (X,Y).
%% Parameters:
%%			1. POS: the animal position.
%%			2. Type: animal type (Knight/Whitewalker/Dragon).
%%			3. ID: animal ID.
%%			4. Radius: radius to be check.

servs2Check(ID, Type, POS, Radius) ->
	Dx = element(1,POS) - ?X_MAXVALUE/2,
	Dy = element(2,POS) - ?Y_MAXVALUE/2,
	case {abs(Dx) < Radius, abs(Dy) < Radius} of
		{false, false} -> % Local server is the relevant one. No need to check radius in other servers.
			ok;
		{false, true}  -> % Local, Up/Down servers is relevant to be check.
			case get(serverName) of
				lu -> checkServ(ID, Type, POS, ld);
				ld -> checkServ(ID, Type, POS, lu);
				ru -> checkServ(ID, Type, POS, rd);
				rd -> checkServ(ID, Type, POS, ru)
			end;
		{true, false}  -> % Local, Left/Right servers is relevant to be check.
			case get(serverName) of
				lu -> checkServ(ID, Type, POS, ru);
				ld -> checkServ(ID, Type, POS, rd);
				ru -> checkServ(ID, Type, POS, lu);
				rd -> checkServ(ID, Type, POS, ld)
			end;
		{true, true}   -> % Check all servers.
			[Srv1,Srv2,Srv3] = getOthers(),
			checkServ(ID, Type, POS, Srv1), 
			checkServ(ID, Type, POS, Srv2),
			checkServ(ID, Type, POS, Srv3) 									
	end.
	
%							 ~~~~~~~~~~~~~~~~~~~~~~~~~~checkServ~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Check radius in "serv" server.
checkServ(ID, Type, POS, Serv) ->
	case Type of
		knight -> square_server:knightTest(POS, ID, Serv);
		dragon -> square_server:dragonTest(POS, ID, Serv);
		whitewalker -> square_server:whitewalkerTest(POS, ID, Serv)
	end.

%							  ~~~~~~~~~~~~~~~~~~~~~~~~~~distance~~~~~~~~~~~~~~~~~~~~~~~~~~~~
distance({X1,Y1}, {X2,Y2}) ->
	math:sqrt((X1-X2)*(X1-X2) + (Y1-Y2)*(Y1-Y2)).

%							 ~~~~~~~~~~~~~~~~~~~~~~~~~~getOthers~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Return the names of all other 3 servers in the game.
getOthers() ->
	case get(serverName) of
		lu -> [ld, ru, rd];
		ld -> [lu, rd, ru];
		ru -> [lu, rd, ld];
		rd -> [ld, ru, lu]
	end.
%						~~~~~~~~~~~~~~~~~~~~~~~~~~~~~getServer~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Get the server name according to the position {X, Y}.
getServer({X,Y}) ->
	case {X > ?X_MAXVALUE/2, (Y > ?Y_MAXVALUE/2)} of
		{false, false} -> ets:lookup_element(squareNodesNames, lu, 2);
		{false, true}  -> ets:lookup_element(squareNodesNames, ld, 2);
		{true, false}  -> ets:lookup_element(squareNodesNames, ru, 2);
		{true, true}   -> ets:lookup_element(squareNodesNames, rd, 2)
	end.


%						~~~~~~~~~~~~~~~~~~~~~~~~~~~move2another~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Move knight/whitewalker/dragon with id "ID" to another server.
move2another(Serv, ID, POS,  Dest, FoodRT, StuffedRT, ETS,KingID) ->
	case global:whereis_name(Serv) of 
		undefined -> io:fwrite("Server ~p Is Crush! Bye!!~n",[Serv]),
				case ets:lookup(ETS, ID) of
					[] -> ignore;
					[{ID,{Type, _Pos, _StateName}}] ->
						delete(get(serverName), ID, kill),
						 case Type of
								knight -> square_server:addKnight(get(serverName), erlang:list_to_atom(erlang:ref_to_list(make_ref())), POS, knight:randDest(POS), FoodRT, StuffedRT);
								dragon -> square_server:addDragon(get(serverName), erlang:list_to_atom(erlang:ref_to_list(make_ref())), POS, knight:randDest(POS), FoodRT, StuffedRT);
								whitewalker -> square_server:addWhitewalker(get(serverName), erlang:list_to_atom(erlang:ref_to_list(make_ref())), POS, knight:randDest(POS), FoodRT, StuffedRT,KingID)
						 end;
					[{ID,{_Type, _Pos, _StateName,theKnightKing}}] ->
						delete(get(serverName), ID, kill),
						square_server:addWhitewalker(get(serverName), erlang:list_to_atom(erlang:ref_to_list(make_ref())), POS, knight:randDest(POS), FoodRT, StuffedRT,KingID)
				end, 
			    ets:delete(ETS, ID);
		_ANY -> case ets:lookup(ETS, ID) of
					[] -> ignore;
					[{ID,{Type, _Pos, _StateName}}] ->
						delete(get(serverName), ID, kill),
						case Type of
							knight -> square_server:addKnight(Serv, ID, POS, Dest, FoodRT, StuffedRT);
							dragon -> square_server:addDragon(Serv, ID, POS, Dest, FoodRT, StuffedRT);
							whitewalker -> square_server:addWhitewalker(Serv, ID, POS, Dest, FoodRT, StuffedRT,KingID)
						end,
						
						ets:delete(ETS, ID);
					[{ID,{_Type, _Pos, _StateName, KingID}}] ->
						delete(get(serverName), ID, kill),
						square_server:addWhitewalker(Serv, ID, POS, Dest, FoodRT, StuffedRT,KingID),
						ets:delete(ETS, ID)
				end
	end.

%					~~~~~~~~~~~~~~~~~~~~~~~~~~~outOfSquare~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Check if new position is out of the server area.
outOfSquare({X,Y}) ->
	case get(serverName) of
		lu -> ((X >= ?X_MAXVALUE/2) and (Y =< ?Y_MAXVALUE/2)) or ((X =< ?X_MAXVALUE/2) and (Y >= ?Y_MAXVALUE/2));
		ld -> ((X < ?X_MAXVALUE/2) and (Y < ?Y_MAXVALUE/2)) or ((X > ?X_MAXVALUE/2) and (Y > ?Y_MAXVALUE/2));
		ru -> ((X < ?X_MAXVALUE/2) and (Y < ?Y_MAXVALUE/2)) or ((X > ?X_MAXVALUE/2) and (Y > ?Y_MAXVALUE/2));
		rd -> ((X >= ?X_MAXVALUE/2) and (Y =< ?Y_MAXVALUE/2)) or ((X =< ?X_MAXVALUE/2) and (Y >= ?Y_MAXVALUE/2))
	end.


%					~~~~~~~~~~~~~~~~~~~~~~~~~~~deleteObjects~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% kills every participant in nodeETS (fsm)
deleteObjects() ->
	TBwk = qlc:q([ID || {ID,{whiteking,_POS,_StNm}} <- ets:table(currETS)]),
	case qlc:eval(TBwk) of
		[] 		->  ok;	
		WhitekingList -> lists:foreach(fun(Participant) -> whiteking:kill(Participant) end, WhitekingList)
	end,

	TBknight = qlc:q([ID || {ID,{knight,_Pos,_StNm}} <- ets:table(currETS)]),
	case qlc:eval(TBknight) of
		[] ->  ok;	
		KnightList -> lists:foreach(fun(Participant) -> knight:kill(Participant) end, KnightList)
	end,
	
	TBdragon = qlc:q([ID || {ID,{dragon,_Pos,_StNm}} <- ets:table(currETS)]),
	case qlc:eval(TBdragon) of
		[] ->  ok;	
		DragonList -> lists:foreach(fun(Participant) -> dragon:kill(Participant) end, DragonList)
	end,

	TBwhitewalker = qlc:q([ID || {ID,{whitewalker,_Pos,_StNm}} <- ets:table(currETS)]),
	case qlc:eval(TBwhitewalker) of
		[] ->  ok;	
		WhitewalkerList -> lists:foreach(fun(Participant) -> whitewalker:kill(Participant) end, WhitewalkerList)
	end.
