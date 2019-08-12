% =================================================================================
% Declarations
% =================================================================================
-module(whitewalker).
-behaviour(gen_fsm).
-include("MACROS.hrl").

% =================================================================================
% Exports
% =================================================================================
-export([init/1]).
-export([walking/2]).
-export([chasing/2]).
-export([eating/2]).
-export([handle_event/3]).
-export([handle_sync_event/4]).
-export([handle_info/3]).
-export([terminate/3]).
-export([code_change/4]).
-export([start_link/7]).
-export([walk/2]).
-export([gotoKnight/3]).
-export([kill/1]).
-export([obstacle/2]).

% =================================================================================
% gen-fsm functions
% =================================================================================
start_link(WhitewalkerID ,Position, Destination,WhitekingRemainingTime, StuffedRemainingTime, ServerName,KingID) -> gen_fsm:start(?MODULE, [WhitewalkerID,Position, Destination,WhitekingRemainingTime, StuffedRemainingTime, ServerName, KingID], []).
walk(WhitewalkerID, Destination) -> gen_fsm:send_event({global,WhitewalkerID}, {walk, Destination}).
gotoKnight(WhitewalkerID, KnightID, KnightPosition) -> gen_fsm:send_event({global,WhitewalkerID}, {srv_gotoKnight, KnightID, KnightPosition}).
obstacle(WhitewalkerID, ObstaclePosition) -> gen_fsm:send_event({global,WhitewalkerID}, {obstacle, ObstaclePosition}).
kill(WhitewalkerID) -> gen_fsm:send_event({global,WhitewalkerID}, kill).


% =================================================================================
% Init
% =================================================================================
init([WhitewalkerID, Position, Destination, WhitekingRemainingTime, StuffedRemainingTime, ServerName,KingID]) ->
	Self = self(),
	spawn(fun() -> global:register_name(WhitewalkerID,Self),io:fwrite("SPAWN LINK id:~w~n", [self()]) end),
	%link(Pid),
	case global:whereis_name(theKnightKing) of
		undefined-> ok;
		_ANY-> link(_ANY)
	end,
	put(whitewalker_id, 		WhitewalkerID),
	put(server_name, 	ServerName),
	put(position, 		Position),
	put(destination, 	Destination),
	put(kingid, KingID),
	process_flag(trap_exit, true),
	io:fwrite("whitewalker id:~w~n", [self()]),
	case StuffedRemainingTime of
		false -> put(stuffedFlag, false);
		Time 	-> setTimeoutStuffed(Time)
	end,
	
	setHungerTimeout(WhitekingRemainingTime),
	setEvent(?CLK, {walk,Destination}),
	% initial whitewalker state is walking.
	{ok, walking, {}}.


% =================================================================================
% Walking state - related functions
% =================================================================================

% ===== walking - walk state =====
% continue walking towards destination, when destination is reached get a new random one
walking({walk, Destination}, StateData) ->
	Position = get(position),
  Speed = getCurrentSpeed(walking),
	NewPosition = getNextPosition(Position, Destination, Speed),
	case distanceFrom(NewPosition, Destination) < Speed of
		true -> setEvent(?CLK, {walk, generateRandomDestination(Position)});
		_Else-> put(position,NewPosition),
						sendInfoToServer(NewPosition, walking),
						setEvent(?CLK, {walk, Destination})
	end,
	case global:whereis_name(theKnightKing) of
		undefined-> ok;
		_ANY-> link(global:whereis_name(theKnightKing))
	end,
    {next_state, walking, StateData};

% ===== walking - gotoKnight state =====
% if whitewalker is stuffed continue walking, otherwise cancel walking event and chase knight
walking({srv_gotoKnight, KnightID, KnightPosition}, StateData) ->
	case get(stuffedFlag) of
		true-> {next_state, walking, StateData};
		false->
			stopEventTimer(),
			put(knightID, KnightID),
			put(destination, KnightPosition),
			setEvent(?CLK, gotoKnight),
    	{next_state, chasing, StateData}
	end;

% 1. unset 'stuffed' flag
% 2. stay in walking state
walking(stuffedTimeout, StateData) ->
	put(stuffedFlag,false),
    {next_state, walking, StateData};

% 1. when towards obstacle cancel walking event
% 2. generate a new destination
% 3. stay in walking state
walking({obstacle, ObstaclePosition}, StateData) ->
	stopEventTimer(),
	setEvent(?CLK, {walk, calculateAlternativeDestination(ObstaclePosition)}),
    {next_state, walking, StateData};

% ===== after hunger timeout cancel walking event and delete from server =====
walking(delete, StateData) ->
	stopEventTimer(),
	square_server:delete(get(server_name), get(whitewalker_id), delete),
	io:fwrite("whitewalker delete~n "),
    {stop, normal, StateData};

% ===== after hunger timeout cancel walking event and delete from server =====
walking(kill, StateData) ->
	stopEventTimer(),
	square_server:delete(get(server_name), get(whitewalker_id), kill),
	io:fwrite("whitewalker kill~n "),
    {stop, normal, StateData}.


% =================================================================================
% Eating state - related functions
% =================================================================================

% ===== after eating function =====
% 1. spawn new whitewalker
% 2. set new timeout
% 3. set walking state
eating(finishEating, StateData) ->
	square_server:addWhitewalker(get(server_name), erlang:list_to_atom(erlang:ref_to_list(make_ref())), 
	get(position), get(position),?WHITEWALKER_TIMEOUT_FOOD,false, get(kingid)),
	%restartFoodTimer(?WHITEWALKER_TIMEOUT_FOOD),
	%continue(?CLK, {walk, get(pos)}),
	setHungerTimeout(?WHITEWALKER_TIMEOUT_FOOD),
	setEvent(?CLK, {walk, get(position)}),
	{next_state, walking, StateData};

% ===== stay in eating state =====
eating({srv_gotoKnight, _KnightID, _KnightPosition}, StateData) ->
	{next_state, eating, StateData};

% ===== stay in eating state =====
eating({obstacle, _ObstaclePosition}, StateData) ->
	{next_state, eating, StateData};

% ===== delete from server: stop timer, notice server with message =====
eating(delete, StateData) ->
	setHungerTimeout(?WHITEWALKER_TIMEOUT_FOOD),
	square_server:delete(get(server_name), get(whitewalker_id), delete),
	{stop, normal, StateData};

% ===== kill from server: stop timer, notice server with message =====
eating(kill, StateData) ->
	setHungerTimeout(?WHITEWALKER_TIMEOUT_FOOD),
	square_server:delete(get(server_name), get(whitewalker_id), kill),
	{stop, normal, StateData}.


% =================================================================================
% Chasing state - related functions
% =================================================================================
% 1. knight was found: switch to walk state
% 2. knight found: get next position to it
% 2.1. knight was caught -> eat it, set new timeout, senf info to server, set eating state
% 2.2. knight wasn't caught -> update info in server, keep chasing
chasing(gotoKnight, StateData) ->
	Position = get(position),
	KnightPosition = get(destination),
	case KnightPosition of
		none -> setEvent(?CLK, {walk, Position}), {next_state, walking, StateData};
		_Else ->	Speed = getCurrentSpeed(chasing), NewPosition = getNextPosition(Position, KnightPosition, Speed),
			case checkForCaughtKnight(NewPosition, KnightPosition) of
				true ->
					eatKnight(),
					setHungerTimeout(?WHITEWALKER_TIMEOUT_FOOD),
					sendInfoToServer(NewPosition,eating),
					{next_state, eating, StateData};
				false ->
					put(position,NewPosition),
					put(knightID, none),
					put(destination, none),
					sendInfoToServer(NewPosition, chasing),
					setEvent(?CLK, gotoKnight),
					{next_state, chasing, StateData}
			end
	end;

% ===== set knightId and destination to it, set chasing state =====
chasing({srv_gotoKnight, KnightID, KnightPosition}, StateData) ->
	put(knightID, KnightID),
	put(destination, KnightPosition),
	{next_state, chasing, StateData};

% ===== stay in chasing state =====
chasing({obstacle, _ObstaclePosition}, StateData) ->
    {next_state, chasing, StateData};

% ===== delete from server: stop timer, notice server with message =====
chasing(delete, StateData) ->
	stopEventTimer(),
	square_server:delete(get(server_name), get(whitewalker_id), delete),
    {stop, normal, StateData};

% ===== kill from server: stop timer, notice server with message =====
chasing(kill, StateData) ->
	stopEventTimer(),
	square_server:delete(get(server_name), get(whitewalker_id), kill),
    {stop, normal, StateData}.




% =================================================================================
% Handlers
% =================================================================================
handle_event(_Event, StateName, StateData) -> io:fwrite("handle_event~n "),{next_state, StateName, StateData}.
handle_sync_event(_Event, _From, StateName, StateData) -> io:fwrite("handle_sync_event~n "), Reply = ok, {reply, Reply, StateName, StateData}.
handle_info(_Info, StateName, StateData) -> 
{_Adir,_Moshe,Reason}=_Info,
	case Reason of

	eaten->
		gen_fsm:send_event_after(0, kill),
		case gen_fsm:cancel_timer(get(whitekingTimeoutRef)) of
				false -> continue;
				_WhitekingRemainingTime -> global:unregister_name(get(whitewalker_id)),
					case get(stuffedEventReference) of
						undefined -> _StuffedRemainingTime = false;
						Ref -> _StuffedRemainingTime = gen_fsm:cancel_timer(Ref)
					end
		end;
		_ANY -> ok
	end,
io:fwrite("handle_info~p~n",[_Info]), {next_state, StateName, StateData}.
terminate(_Reason, _StateName, _StatData) -> io:fwrite("terminate reson: ~p~n", [_Reason]), ok, {next_state, _StateName, _StatData}.
code_change(_OldVsn, StateName, StateData, _Extra) -> io:fwrite("code_change~n"), {ok, StateName, StateData}.

% =================================================================================
% Whitewalker Functions: eatKnight, checkForCaughtKnight, getCurrentSpeed, calculateAlternativeDestination,
% generateRandomDestination, generateNewDestinationInFrame, distanceFrom, outOfServerBorders,
% getNextPosition
% =================================================================================

% ===== eat knight method =====
% 1. kill the caught knight
% 2. set event of eating
% 3. set stuffed flag
% 4. set eaten knight counter
eatKnight() ->
	knight:kill(get(knightID)),
	setEvent(?WHITEWALKER_EATING_TIMEOUT, finishEating),
	setTimeoutStuffed(?WHITEWALKER_TIMEOUT_STUFFED).


% ===== return true when distance from the whitewalker and knight is close enough, otherwise return false =====
checkForCaughtKnight(WhitewalkerPos, KnightPosition) ->
	case distanceFrom(WhitewalkerPos, KnightPosition) < ?MINIMUM_RANGE/2 of
		true  -> true;
		false -> false
	end.

% ===== get the actual speed based on the state =====
getCurrentSpeed(State) ->
	case State of
		chasing 	-> ?WHITEWALKER_FAST_SPEED;
		_Else    	-> ?WHITEWALKER_SLOW_SPEED
	end.

% ===== get a new alternative destination to pass an obstacle =====
% 1.1. case of obstacle is from up or down: get relative (angle = PI/2) from it
% 1.2. case of obstacle is from right or left: get relative (angle = arctan(DY/DX)) from it
% 2. check where is obstacle is placed and get the opposite direction from it
% 3. calculate new destination to avoid the obstacle
calculateAlternativeDestination({X_Obstacle,Y_Obstacle}) ->
	{X,Y} = get(position),
	case  X_Obstacle == X of
		true  -> 
			case Y_Obstacle >= Y of
				true  -> Angle = math:pi()/2;
				false -> Angle = (-1) * math:pi()/2
			end;
		false -> Angle = math:atan((Y_Obstacle-Y)/(X_Obstacle-X))
	end,
	case  X_Obstacle < X of
		true ->  Sign = 1;
		false -> Sign = -1
	end,
	X_Delta = Sign * ?MINIMUM_RANGE * math:cos(Angle),
	Y_Delta = Sign * ?MINIMUM_RANGE * math:sin(Angle),
	Destination = generateNewDestinationInFrame({X + X_Delta, Y + Y_Delta}),
	put(destination, Destination),
	Destination.

% ===== get a new random destination =====
generateRandomDestination({X,Y}) ->
	random:seed(erlang:now()),
	% Random X_Sign,Y_Sign is between {-1,1}
	% Random X_Delta,Y_Delta is between {0,?RANDOM_RANGE}
	X_Sign = 2*random:uniform(2) - 3,
	Y_Sign = 2*random:uniform(2) - 3,
	X_Delta = random:uniform(?RANDOM_RANGE),
  Y_Delta = random:uniform(?RANDOM_RANGE),
	Destination = generateNewDestinationInFrame({X + X_Sign * X_Delta, Y + Y_Sign * Y_Delta}),
	put(destination, Destination),
	Destination.

% ===== check if {X,Y] are valid and get a new random destination =====
generateNewDestinationInFrame({X,Y}) ->
	case (X >= ?X_MAXVALUE - ?MINIMUM_RANGE)  of
		true -> X_NewDestination = ?X_MAXVALUE - ?MINIMUM_RANGE;
		false->
			case (X < ?MINIMUM_RANGE + ?MINIMUM_RANGE)  of
				true -> X_NewDestination = ?MINIMUM_RANGE + ?MINIMUM_RANGE;
				false-> X_NewDestination = X
			end
	end,
	case (Y >= ?Y_MAXVALUE - ?MINIMUM_RANGE)  of
		true -> Y_NewDestination = ?Y_MAXVALUE - ?MINIMUM_RANGE;
		false->
			case (Y < ?MINIMUM_RANGE)  of
				true -> Y_NewDestination = ?MINIMUM_RANGE;
				false-> Y_NewDestination = Y
			end
	end,
	{round(X_NewDestination), round(Y_NewDestination)}.

% ===== distance from one point to another =====
distanceFrom({X1,Y1}, {X2,Y2}) ->
	math:sqrt((X1-X2)*(X1-X2) + (Y1-Y2)*(Y1-Y2)).

% ===== outOfServerBorders =====
% 1. check if knight is out from its server borders
% 2.1. if needed, delete from server
% 2.2. cancel timeout and get the remaining time of it
% 2.3. send the nearby server all parameters to move object to it
outOfServerBorders(NewPosition) ->
	case getScreenName(NewPosition) of
		true  -> gen_fsm:send_event_after(0, delete),
			case gen_fsm:cancel_timer(get(whitekingTimeoutRef)) of
				false -> continue;
				WhitekingRemainingTime -> global:unregister_name(get(whitewalker_id)),
					case get(stuffedEventReference) of
						undefined -> StuffedRemainingTime = false;
						Ref -> StuffedRemainingTime = gen_fsm:cancel_timer(Ref)
					end,
					square_server:changeServer(get(server_name), get(whitewalker_id), NewPosition, get(destination), WhitekingRemainingTime, StuffedRemainingTime,get(kingid))
			end;
		false -> continue
	end.

% ===== get the new position on a straight line to the destination based on speed =====
% 1. DY = 0 -> add speed to X movement
% 2. DX > DY -> add speed to X movement add relative (DY/DX)(speed) to Y movement
% 3. DY > DX -> add speed to Y movement add relative (DX/DY)(speed) to X movement
getNextPosition(_Position = {X_Position,Y_Position}, _Destination = {X_Destination,Y_Destination}, Speed) ->
	X_Delta = abs(X_Destination - X_Position),
	Y_Delta = abs(Y_Destination - Y_Position),
	case {X_Delta, Y_Delta} of
		% destination is on X axis
		{X_Delta, Y_Delta} when Y_Delta == 0 ->
			case (X_Destination - X_Position) of
				% same position
				X_Result when X_Result == 0 ->
					X_NewPosition = X_Position,
					Y_NewPosition = Y_Position;
				% go forward
				X_Result when X_Result > 0 ->
					X_NewPosition = X_Position + Speed,
					Y_NewPosition = Y_Position;
				% go backwards
				X_Result when X_Result < 0 ->
					X_NewPosition = X_Position - Speed,
					Y_NewPosition = Y_Position
			end;
		% DX >= DY
		{X_Delta,Y_Delta} when X_Delta/Y_Delta >= 1 ->
			case (X_Destination - X_Position) of
				X_Result when X_Result > 0 ->
					X_NewPosition = X_Position + Speed,
					Y_NewPosition = Y_Position +
						((Y_Destination - Y_Position)/(X_Destination - X_Position))*(Speed);
				X_Result when X_Result < 0 ->
					X_NewPosition = X_Position - Speed,
					Y_NewPosition = Y_Position +
						((Y_Destination - Y_Position)/(X_Destination - X_Position))*(Speed)*(-1)
			end;
		% DX < DY
		{X_Delta,Y_Delta} when X_Delta/Y_Delta < 1 ->
			case (Y_Destination-Y_Position) of
				Y_Result when Y_Result > 0 ->
					Y_NewPosition = Y_Position + Speed,
					X_NewPosition = X_Position +
						((X_Destination - X_Position)/(Y_Destination - Y_Position))*(Speed);
				Y_Result when Y_Result < 0 ->
					Y_NewPosition = Y_Position - Speed,
					X_NewPosition = X_Position +
						((X_Destination - X_Position)/(Y_Destination - Y_Position))*(Speed)*(-1)
			end
	end,
	NewPosition = {round(X_NewPosition),round(Y_NewPosition)},
	outOfServerBorders(NewPosition),
	NewPosition.


% =================================================================================
% Server and Timer Functions: setEvent, setHungerTimeout, setTimeoutStuffed,
% stopEventTimer, sendInfoToServer, getScreenName
% =================================================================================

% ===== function to send events after delay =====
setEvent(TimeDelay, Event) ->
	EventReference = gen_fsm:send_event_after(TimeDelay, Event),
	put(eventRef, EventReference).

% ===== cancel the current whiteking timeout and start a new one =====
setHungerTimeout(TimeDelay) ->
	case get(whitekingTimeoutRef) of
		undefined -> 	EventReference = gen_fsm:send_event_after(TimeDelay, kill), put(whitekingTimeoutRef, EventReference);
		PreRef -> 		gen_fsm:cancel_timer(PreRef), EventReference = gen_fsm:send_event_after(TimeDelay, kill), put(whitekingTimeoutRef, EventReference)
	end.

% ===== set the stuffed flag and timeout =====
setTimeoutStuffed(TimeDelay) ->
	EventReference = gen_fsm:send_event_after(TimeDelay, stuffedTimeout),
	put(stuffedEventReference, EventReference),
	put(stuffedFlag, true).

% ===== cancel timer of current event =====
stopEventTimer() ->
	CurrentEvent = get(eventRef),
	io:fwrite("event is ~p~n",[CurrentEvent]),
	gen_fsm:cancel_timer(CurrentEvent).

% ===== send the server updated information about the whitewalker =====
sendInfoToServer(NewPosition, StateName) ->
	case square_server:checkRadsAndUpdate(get(server_name),get(whitewalker_id), whitewalker, NewPosition, StateName) of
		error_not_exists -> not_exists;
		_Else-> ok
	end.

% ===== return the screen name based on X,Y =====
getScreenName({X, Y}) ->
	case get(server_name) of
		lu -> ((X >= ?X_MAXVALUE/2) and (Y =< ?Y_MAXVALUE/2)) or ((X =< ?X_MAXVALUE/2) and (Y >= ?Y_MAXVALUE/2));
		ld -> ((X < ?X_MAXVALUE/2) and (Y < ?Y_MAXVALUE/2)) or ((X > ?X_MAXVALUE/2) and (Y > ?Y_MAXVALUE/2));
		ru -> ((X < ?X_MAXVALUE/2) and (Y < ?Y_MAXVALUE/2)) or ((X > ?X_MAXVALUE/2) and (Y > ?Y_MAXVALUE/2));
		rd -> ((X >= ?X_MAXVALUE/2) and (Y =< ?Y_MAXVALUE/2)) or ((X =< ?X_MAXVALUE/2) and (Y >= ?Y_MAXVALUE/2))
	end.
