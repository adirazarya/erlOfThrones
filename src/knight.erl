% =================================================================================
% Declarations
% =================================================================================
-module(knight).
-behaviour(gen_fsm).
-include("MACROS.hrl").


% =================================================================================
% Exports
% =================================================================================
-export([init/1]).
-export([walking/2]).
-export([eating/2]).
-export([handle_event/3]).
-export([handle_sync_event/4]).
-export([handle_info/3]).
-export([terminate/3]).
-export([code_change/4]).
-export([start_link/6]).
-export([walk/2]).
-export([gotoWhiteking/2]).
-export([escape/2]).
-export([walking4Food/2]).
-export([escaping/2]).
-export([kill/1]).
-export([obstacle/2]).
-export([randDest/1]).

start_link(ID, Pos, Dest,FoodRT, StuffedRT, ServerName) ->
    gen_fsm:start(?MODULE, [ID,Pos, Dest,FoodRT, StuffedRT,ServerName], []).
	
% ============ Knight events ===========
walk(ID, Dest) ->
	gen_fsm:send_event({global,ID}, {walk, Dest}).
gotoWhiteking(ID, Wpos) ->
	gen_fsm:send_event({global,ID}, {srv_gotoWhiteking, Wpos}).
escape(ID, Hpos) ->
	gen_fsm:send_event({global,ID}, {srv_escape, Hpos}).
obstacle(ID, ObPos) -> 
	gen_fsm:send_event({global,ID}, {obstacle, ObPos}).
kill(ID) -> 
	gen_fsm:send_event({global,ID}, kill).

%% ====================================================================
%% Functions Implementation
%% ====================================================================

% 							=========================================== init/1 =======================================
init([ID, Pos, Dest,FoodRT, StuffedRT, ServerName]) ->
	
	erlang:link(global:whereis_name(ServerName)),
	Self = self(),
	spawn(fun() -> global:register_name(ID,Self) end),

	put(id, ID),
	put(server, ServerName),
	put(pos, Pos),
	put(dest, Dest),
	put(whitewalkerPos, false),
	
	case StuffedRT of
		false ->
			put(stuffed, false);
		RT ->
			startStuffedTimer(RT)
	end,
	restartFoodTimer(FoodRT),
	continue(?CLK, {walk, Dest}),              % Start walking to destination.
    {ok, walking, {}}.

% 							=========================================== KNIGHT STATES =======================================

%% state_name/2
%% _____________________________________________________________________
%% ______________________________State 1: walking_______________________________

%% Get walk event while the knight is walking.
%% Check if you are nearby your destination:
%%										  TRUE : go to a new destination randomally and continue walking
%%										  FALSE : update you server with the new position and state (sendPOS).
walking({walk, Dest}, StateData) ->
    Pos = get(pos),
    Step = getCurrentSpeed(walking), 										% Choose SLOW_SPEED/FAST_SPEED
	NextPos = getNextPos(Pos, Dest, Step), 							% Get the next step.
	case distanceFrom(NextPos, Dest) < Step of							% !!!!!!!!!!!!!!! REPLACE STEP with ?FAST_SPEED !!!!!!!!!!!!!
		true -> 
				NewDest=randDest(Pos),
				continue(?CLK, {walk, NewDest}); 					% Continue walking with a new destination.
		_Else-> 
				put(pos,NextPos),									% Go to the next position.
				sendPOS(NextPos, walking),
			    continue(?CLK, {walk, Dest})						% Continue walking to your destination.
	end,
    {next_state, walking, StateData};

%% Get gotoWhiteking event while the knight is walking.
%% Check if you are stuffed:
%%							TRUE : Continue walking.
%%							FALSE : Change state to walking4Food state.
walking({srv_gotoWhiteking, Wpos}, StateData) ->                    % Knight is near a whiteking, into whiteking_radius area.
	case get(stuffed) of
		true-> {next_state, walking, StateData};					% Don't eat the whiteking, continue walking.
		false->
			cancelCurrentEvent(),                                   % Cancel walking event.
			put(whitekingFlag, true),								
			put(dest, Wpos),										% Change destination to whiteking position.
			continue(?CLK, {gotoWhiteking, Wpos}),               	% Generate gotoWhiteking event.
    		{next_state, walking4Food, StateData}					% Next_state = eatingWhiteking.
	end;
	
%% Get stuffedTimeout event while the knight is walking.
%% Change stuffed status to false, continue walkmig.
walking(stuffedTimeout, StateData) ->                              
	put(stuffed,false),												% Switch to not stuffed.
    {next_state, walking, StateData};

%% Get escape event while the knight is walking.
%% Change the knight state to escaping.
walking({srv_escape, Hpos}, _StateData) ->                       	% Knight is near a Whitewalker, into whitewalker_radius area.
	put(whitewalkerPos, Hpos),
	cancelCurrentEvent(),                                           % Cancel walking event.
	continue(?CLK, {escape, get(pos)}),                           	% Generate escaping event.
	{next_state, escaping, {true}};                                 
	
%% Get obstacle event while the knight is walking.
%% Calculate the new destination according to obstacle position.
walking({obstacle, ObstclPos}, StateData) ->                      	% Get into obstacle radius.
	cancelCurrentEvent(),   										% Cancel walking event.
	Dest = calcObstacleDest(ObstclPos),
	continue(?CLK, {walk, Dest}),         							% Generate the new destination.
    {next_state, walking, StateData};

walking(delete, StateData) ->                                      % Timeout hungry.
	cancelCurrentEvent(),
	square_server:delete(get(server), get(id), delete),
    {stop, normal, StateData};
    
walking(kill, StateData) ->                                       
	cancelCurrentEvent(),
	square_server:delete(get(server), get(id) ,kill),
    {stop, normal, StateData}.

%%_____________________________________________________________________
%%_____________________________State 2: walking4Food_____________________________

%% Get gotoWhiteking event while walking in order to eat.
%% Check is whiteking is exist:
%%							False: another knight eat the relevant whiteking -> continue walking (change state to walking).
%%							True: go ahead to the whiteking.
walking4Food({gotoWhiteking, Wpos}, StateData) ->
	POS = get(pos),
	case get(whitekingFlag) of
		false ->
			continue(?CLK, {walk, POS}),
			put(dest, POS),
			{next_state, walking, StateData};
		true ->
		
			Step = getCurrentSpeed(walking),
			NextPos = getNextPos(POS, Wpos, Step),
			case distanceFrom(NextPos, Wpos) =< ?MINIMUM_RANGE/2 of
				true ->  												% Reaches whiteking
						updateEatenW(Wpos),
						sendPOS(NextPos, eating),
						restartFoodTimer(?KNIGHT_TIMEOUT_FOOD),
						continue(?KNIGHT_EATING_TIMEOUT, finishEating),		% after eating_timeout send finishEating event.
						{next_state, eating, StateData};
				_Else->
						put(pos,NextPos),
						put(whitekingFlag, false),						% lock the whiteking from another knight.
						sendPOS(NextPos, walking),					
					    continue(?CLK, {gotoWhiteking, Wpos}),
						{next_state, walking4Food, StateData}
			end
	end;

%% Get server gotoWhiteking event while walking in order to eat.
%% It means, the server found a whiteking for me, so the whiteking is exist -> whitekingFlag = true.
walking4Food({srv_gotoWhiteking, _Wpos}, StateData) ->
	put(whitekingFlag, true),
    {next_state, walking4Food, StateData};

%% Get server escape event while walking in order to eat.
walking4Food({srv_escape, Hpos}, _StateData) ->                       % Get nearby a whitewalker, into whitewalker radius.
	put(whitewalkerPos, Hpos),	
	cancelCurrentEvent(),                                               % Cancel walking4Food state.
	continue(?CLK, {escape, get(pos)}),                           		% Generate escaping event.
	{next_state, escaping, {true}};                                  	

walking4Food({obstacle,_Obs_XY}, StateData) ->                    		% Get into obstacle radius.
    {next_state, walking4Food, StateData};

walking4Food(delete, StateData) ->                                     
	cancelCurrentEvent(),
	square_server:delete(get(server), get(id), delete),
    {stop, normal, StateData};

walking4Food(kill, StateData) ->                                      
	cancelCurrentEvent(),
	square_server:delete(get(server), get(id) ,kill),
    {stop, normal, StateData}.

%%_____________________________________________________________________
%%______________________________eating_________________________________
%% finishEating event received while knight is in eating state.
%% duplicate the knight.
eating(finishEating, StateData) ->
	%square_server:addKnight(get(server), erlang:list_to_atom(erlang:ref_to_list(make_ref())),
		%get(pos), get(pos),?KNIGHT_TIMEOUT_FOOD,false),
	restartFoodTimer(?KNIGHT_TIMEOUT_FOOD),
	continue(?CLK, {walk, get(pos)}),
	{next_state, walking, StateData};

%% server escape event received while knight is in eating state.
eating({srv_escape, Hpos}, _StateData) ->
	put(whitewalkerPos, Hpos),
	cancelCurrentEvent(),                                         % Cancel finishEating event.
	continue(?CLK, {escape, get(pos)}),                           % Generate escaping event.	
	{next_state, escaping, {true}};
	
%% Obstacle event received while knight is in eating state.	
eating({obstacle, _Obs_XY}, StateData) ->
	{next_state, eating, StateData};

%% Obstacle event received while knight is in eating state.
eating({srv_gotoWhiteking, _Wpos}, StateData) ->               	  %Ignore.
    {next_state, eating, StateData};

eating(delete, StateData) ->                                      % Timeout hungry.
	cancelCurrentEvent(),
	square_server:delete(get(server), get(id), delete),
    {stop, normal, StateData};

eating(kill, StateData) ->                                         % Timeout hungry.
	cancelCurrentEvent(),
	square_server:delete(get(server), get(id) ,kill),
    {stop, normal, StateData};

eating(All, _StateData) ->
	io:fwrite("~p~n",[All]).
%%_____________________________________________________________________
%%______________________________escaping_______________________________

escaping({escape, Dest}, StateData) ->
	EscStatus = element(1, StateData),
	case EscStatus of
		true->    													% Stil in Whitewalker radius.
			Pos = get(pos),
			Step = getCurrentSpeed(escaping),
			NextPos = getNextPos(Pos, Dest, Step),
			case distanceFrom(NextPos, Dest) < Step of					% !!!!!! REPLACE Step with ?FAST_SPEED.
				true -> 				
						sendPOS(NextPos, escaping),
						Rand = randDest(Pos),
						continue(?CLK, {escape, Rand });
				false-> 
						put(pos,NextPos),
						sendPOS(NextPos, escaping),
					    continue(?CLK, {escape, Dest})
			end,
			put(whitewalkerPos, false),
			{next_state, escaping, {false}};
		false->     												% Out of whitewalker radius (ext_escape hasn't been recieved)
			continue(?CLK, {walk, get(pos)}),
			{next_state, walking, StateData}
	end;

escaping({srv_escape, Hpos}, _StateData) ->                        % Already in, 
	put(whitewalkerPosPos, Hpos),
	{next_state, escaping, {true}};                                 %  update EscStatus = true.

escaping({srv_gotoWhiteking, _Wpos}, StateData) ->                 	% Ignore.
    {next_state, escaping, StateData};

escaping(stuffedTimeout, StateData) ->                              % Switch to not stuffed.
	put(stuffed,false),
    {next_state, escaping, StateData};

escaping({obstacle, Obs_XY}, StateData) ->
	cancelCurrentEvent(),                                            % Cancel moving event.
	continue(?CLK, {escape, calcObstacleDest(Obs_XY)}),     		 % Generate with alternate destination.
	{next_state, escaping, StateData};

escaping(delete, StateData) ->                                        % Timeout hungry.
	cancelCurrentEvent(),
	square_server:delete(get(server), get(id), delete),
    {stop, normal, StateData};

escaping(kill, StateData) ->                                         % Timeout hungry.
	cancelCurrentEvent(),
	square_server:delete(get(server), get(id) ,kill),
    {stop, normal, StateData}.

	
%% handle_event/3
%% ====================================================================
handle_event(_Event, StateName, StateData) ->                        	% Kill event!
    {next_state, StateName, StateData}.

%% handle_sync_event/4
%% ====================================================================
handle_sync_event(_Event, _From, StateName, StateData) ->
    Reply = ok,
    {reply, Reply, StateName, StateData}.


%% handle_info/3
%% ====================================================================
handle_info(_Info, StateName, StateData) ->
    {next_state, StateName, StateData}.

%% terminate/3
%% ====================================================================
terminate(_Reason, _StateName, _StatData) ->
    ok.

%% code_change/4
%% ====================================================================
code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.

%% ====================================================================
%% Internal functions
%% ====================================================================

%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~continue~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Wait for "delay" period time.
%% Send the Event again.
continue(Delay, Event) ->
	EventRef = gen_fsm:send_event_after(Delay, Event),
	put(currentEventRef, EventRef).

%~~~~~~~~~~~~~~~~~~~~~~~~~~~ restartFoodTimer ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Cancel the current food timer.
%% Initialize a new food time.
restartFoodTimer(Time) ->
	case get(timoutfoodRef) of
		undefined -> 
			EventRef = gen_fsm:send_event_after(Time, kill),
			put(timoutfoodRef, EventRef);
		PreRef ->
			gen_fsm:cancel_timer(PreRef),
			EventRef = gen_fsm:send_event_after(Time, kill),
			put(timoutfoodRef, EventRef)
	end.

%~~~~~~~~~~~~~~~~~~~~~~~~~ startStuffedTimer ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Cancel the current stufed timer.
%% Initialize a new stuffed timer with time "RT".
startStuffedTimer(RT) ->
	Stuffed = gen_fsm:send_event_after(RT, stuffedTimeout),
	put(stuffedEvent, Stuffed),
	put(stuffed, true).
%~~~~~~~~~~~~~~~~~~~~~~~~cancelCurrentEvent~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Canceling the current event using the suitable timer ref.
cancelCurrentEvent() ->
	CurrentEvent = get(currentEventRef),
	gen_fsm:cancel_timer(CurrentEvent).

%~~~~~~~~~~~~~~~~~~~~~~~~~~~sendPOS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% For every new position update the relevant server the new position and state.
%% The server will check radiuses and update the knight state accordingly.
sendPOS(POS, StateName) ->
	case square_server:checkRadsAndUpdate(get(server),get(id), knight, POS, StateName) of
		error_not_exists -> not_exists;
		_UPdated -> ok
	end.

%~~~~~~~~~~~~~~~~~~~~~~~~ updateEatenW~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Spawn a knight
%% Start stuffed timer.
updateEatenW(Wpos) ->
	square_server:whitekingEaten(get(server), Wpos),                  	% Update the server, a whiteking was eaten.
	startStuffedTimer(?KNIGHT_TIMEOUT_STUFFED).							% Start the stuffed timer

	
%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~getCurrentSpeed~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Return the step according to the positon and state.
getCurrentSpeed(State) ->
			case State of
				escaping -> ?KNIGHT_FAST_SPEED;
				_Else    -> ?KNIGHT_SLOW_SPEED
			end.

%~~~~~~~~~~~~~~~~~~~~~~~~~~ pos2pixel ~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Get pixels in the screen by the position (X,Y).
pos2pixel({X,Y}) ->
	% Check if X in screen
	case (X >= ?X_MAXVALUE - ?MINIMUM_RANGE)  of
		true -> DesX = ?X_MAXVALUE - ?MINIMUM_RANGE;
		false-> 
			case (X < ?MINIMUM_RANGE + ?MINIMUM_RANGE)  of
				true -> DesX = ?MINIMUM_RANGE + ?MINIMUM_RANGE;
				false-> DesX = X
			end
	end,
	% Check if Y in screen
	case (Y >= ?Y_MAXVALUE - ?MINIMUM_RANGE)  of
		true -> DesY = ?Y_MAXVALUE - ?MINIMUM_RANGE;
		false-> 
			case (Y < ?MINIMUM_RANGE)  of
				true -> DesY = ?MINIMUM_RANGE;
				false-> DesY = Y
			end
	end,
	{round(DesX), round(DesY)}.

%~~~~~~~~~~~~~~~~~~~~~~~~ calcObstacleDest ~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Calculate alternative distination in order to get away of an obsticale at {ObsX,ObsY}.
calcObstacleDest({Obs_X,Obs_Y}) ->
	{X,Y} = get(pos),
	case  Obs_X == X  of
		true  -> 
			case Obs_Y >= Y of
				true  -> Teta = math:pi()/2;
				false -> Teta = (-1) * math:pi()/2
			end;
		false -> Teta = math:atan((Obs_Y-Y)/(Obs_X-X))
	end,	
	case  Obs_X < X of
		true ->  Sign = 1;
		false -> Sign = -1
	end,
	Dx = Sign * ?MINIMUM_RANGE * math:cos(Teta),
	Dy = Sign * ?MINIMUM_RANGE * math:sin(Teta),
	Dest = pos2pixel({X + Dx, Y + Dy}),
	put(dest, Dest),
	Dest.

%~~~~~~~~~~~~~~~~~~~~~~~~ randDest ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Returns a random distenation given the position (X,Y).
randDest({X,Y}) ->
	random:seed(erlang:now()),
	SignX = 2*random:uniform(2) - 3,                                 % Random sgin {-1,1}
	SignY = 2*random:uniform(2) - 3,                                 % Random sgin {-1,1}
	Dx = random:uniform(?RANDOM_RANGE),                              % Random delta_x
    Dy = random:uniform(?RANDOM_RANGE),                              % Random delta_y

	Dest = pos2pixel({X + SignX * Dx,
					         Y + SignY * Dy}),
	put(dest, Dest),
	Dest.

%~~~~~~~~~~~~~~~~~~~~~~~~~~~isOut~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Returns a new valid random distenation.
isOut({X, Y}) ->
	case get(server) of
		lu -> ((X >= ?X_MAXVALUE/2) and (Y =< ?Y_MAXVALUE/2)) or ((X =< ?X_MAXVALUE/2) and (Y >= ?Y_MAXVALUE/2));
		ld -> ((X < ?X_MAXVALUE/2) and (Y < ?Y_MAXVALUE/2)) or ((X > ?X_MAXVALUE/2) and (Y > ?Y_MAXVALUE/2));
		ru -> ((X < ?X_MAXVALUE/2) and (Y < ?Y_MAXVALUE/2)) or ((X > ?X_MAXVALUE/2) and (Y > ?Y_MAXVALUE/2));
		rd -> ((X >= ?X_MAXVALUE/2) and (Y =< ?Y_MAXVALUE/2)) or ((X =< ?X_MAXVALUE/2) and (Y >= ?Y_MAXVALUE/2))
	end.

%~~~~~~~~~~~~~~~~~~~~~~~~~ checkChangeServer ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Check if the knight is outside it's server area. if so, sends the server "changeServer" msg. 
checkChangeServer(POS) ->
	case isOut(POS) of
		true  -> 
			gen_fsm:send_event_after(0, delete),						% Knight kill itself.
			case gen_fsm:cancel_timer(get(timoutfoodRef)) of
				false 		   -> continue;
				FoodRT ->
					global:unregister_name(get(id)),
					case get(stuffedEventRef) of
						undefined -> StuffedRT = false;
						Time 	  -> StuffedRT = gen_fsm:cancel_timer(Time)
					end,					
					square_server:changeServer(get(server), get(id), POS, get(dest),
											FoodRT, StuffedRT,get(id))
					
			end;
		false -> continue
	end.

%~~~~~~~~~~~~~~~~~~~~~~~~~~getNextPos~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
%% Returns the new position(X,Y) according to the knight current position, destination and step type.
%% Knight swin on a straight line.
%% Parameters: 
%%			1. POS: current position.
%%			2. Dest_POS: destination position.
%%			3. Step: step type.
%% Return: NextPos- next position (X,Y).

getNextPos(_POS = {X,Y}, _Dest_POS = {DestX,DestY}, Step) ->
	Dx = abs(DestX-X),
	Dy = abs(DestY-Y),
	case {Dx,Dy} of
		{Dx,Dy} when Dy==0 ->
			case (DestX-X) of
				D when D==0 -> 
					Next_X = X,
					Next_Y = Y;
				D when D>0 -> 
					Next_X = X+Step,
					Next_Y = Y;
				D when D<0 -> 
					Next_X = X-Step,
					Next_Y = Y
			end;
		{Dx,Dy} when Dx/Dy>=1 ->
			case (DestX-X) of
				D when D==0 -> 
					Next_X = X,
					Next_Y = Y+Step;
				D when D>0 -> 
					Next_X = X+Step,
					Next_Y = Y + ((DestY-Y)/(DestX-X))*(Step);
				D when D<0 -> 
					Next_X = X-Step,
					Next_Y = Y + ((DestY-Y)/(DestX-X))*(-1)*(Step)				
			end;
		{Dx,Dy} when Dx/Dy<1 ->
			case (DestY-Y) of
				D when D>0 -> 
					Next_Y = Y+Step,
					Next_X = X + ((DestX-X)/(DestY-Y))*(Step);
				D when D<0 -> 
					Next_Y = Y-Step,
					Next_X = X + ((DestX-X)/(DestY-Y))*(-1)*(Step)		
			end
	end,
	NextPos = {round(Next_X),round(Next_Y)},
	case get(whitewalkerPos) of
		false -> checkChangeServer(NextPos);
		_Else ->
			case distanceFrom(get(pos),get(whitewalkerPos)) < ?MINIMUM_RANGE of
				true -> caught;
				false -> checkChangeServer(NextPos)
			end
	end,
	NextPos.

%~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~distanceFrom~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
distanceFrom({X1,Y1}, {X2,Y2}) ->
	math:sqrt((X1-X2)*(X1-X2) + (Y1-Y2)*(Y1-Y2)).
