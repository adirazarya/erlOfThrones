% =================================================================================
% Declarations
% =================================================================================
-module(wx_server).
-behaviour(wx_object).
-include_lib("wx/include/wx.hrl").
-include_lib("stdlib/include/qlc.hrl").
-include("MACROS.hrl").

% =================================================================================
% Exports
% =================================================================================
-export([etsTableUpdate/3]).
-export([removeQuarter/2]).
-export([removeConnectionStatus/2]).
-export([addWhiteking/3]).

-export([start/0]).
-export([init/1]).

-export([handle_event/2]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).

-export([terminate/2]).
-export([code_change/3]).

-export([createScreenMonitor/0]).
-export([monitorReceiveLoop/1]).
-export([serverReconnection/5]).



% =================================================================================
% Definitions of screens nodes names
% =================================================================================
-define(LU_NODE, 'lu@007-lnx-f2').
-define(RU_NODE, 'ru@007-lnx-f2').
-define(LD_NODE, 'ld@007-lnx-f2').
-define(RD_NODE, 'rd@007-lnx-f2').
-define(SCREENS, [?LU_NODE,
  ?LD_NODE,
  ?RU_NODE,
  ?RD_NODE]).

% =================================================================================
% Screen server state saved as a record
% =================================================================================
-record(state, {panel, frame, self, objects, menu, selectedObject, monitor, cursorKnight, cursorDragon, cursorWhiteking}).

% =================================================================================
% Functions to use from remote screens-servers: etsTableUpdate,	removeQuarter,	removeConnectionStatus,	addWhiteking
% =================================================================================
etsTableUpdate(ListOfEntries,RemoveObjects,Server) -> gen_server:cast(Server,{etsTableUpdate,ListOfEntries,RemoveObjects}).
removeQuarter(Quarter,WxServer) -> gen_server:cast(WxServer,{removeQuarter, Quarter}).
removeConnectionStatus(Server, WxServer) -> gen_server:cast(WxServer,{removeConnectionStatus, Server}).
addWhiteking(ObjectID, ObjectPosition, WxServer) -> gen_server:cast(WxServer,{addWhiteking, ObjectID, ObjectPosition}).

% =================================================================================
% Starting Functions: start, init, initialize
% =================================================================================

% ===== Start function - compile all relevant files, create new Server, register global to current =====
start() ->
  compile:file(square_server),
  compile:file(knight),
  compile:file(whitewalker),
  compile:file(whiteking),
  compile:file(dragon),
  Server = wx:new(),
  wx_object:start_link({global, wx_server},?MODULE, Server, []).

% ===== Initialize function  =====
init(Server) ->
  wx:batch(fun() -> initialize(Server) end).

initialize(Server) ->

  % wx_server - global registration
  global:register_name(wx_server,self()),
  spawn(fun() ->
    rpc:multicall(?SCREENS,compile,file,[square_server]),
    rpc:multicall(?SCREENS,compile,file,[whitewalker]),
    rpc:multicall(?SCREENS,compile,file,[knight]),
	rpc:multicall(?SCREENS,compile,file,[dragon]),
    rpc:multicall(?SCREENS,compile,file,[whiteking]),
    rpc:multicall(?SCREENS,compile,file,[wx_server]),
    rpc:call(?LU_NODE, square_server, start, [?LU]),
    rpc:call(?LD_NODE, square_server, start, [?LD]),
    rpc:call(?RU_NODE, square_server, start, [?RU]),
    rpc:call(?RD_NODE, square_server, start, [?RD])  end),

  % Create a monitor to other screens
  ScreensMonitor = spawn(fun() -> createScreenMonitor() end),

  % ETS table of objects
  ets:new(objects, [set,public,named_table]),

  % ETS table of inforamation
  ets:new(info,   [set,public,named_table]),

  % ETS table of inforamation
  ets:new(luEts,   [set,public,named_table]),
  ets:new(ldEts,   [set,public,named_table]),
  ets:new(ruEts,   [set,public,named_table]),
  ets:new(rdEts,   [set,public,named_table]),
  
  % ETS table of nodes
  ets:new(nodesNames,   [set,public,named_table]),
  ets:insert(nodesNames,{lu,?LU}),
  ets:insert(nodesNames,{ld,?LD}),
  ets:insert(nodesNames,{ru,?RU}),
  ets:insert(nodesNames,{rd,?RD}),
  
  % Add to ETS table of objects - 'Connection' pictures
  ets:insert(objects, [			{?LU,	{connectionImage,?LU_CONNECTION_IMAGE_POSITION},x,x},
    {?LD,	{connectionImage,?LD_CONNECTION_IMAGE_POSITION},x,x},
    {?RU,	{connectionImage,?RU_CONNECTION_IMAGE_POSITION},x,x},
    {?RD,	{connectionImage,?RD_CONNECTION_IMAGE_POSITION},x,x}]),

  % Add to ETS table of info - starting count values of objects
  ets:insert(info, 				[{whitewalkersAlive 		,0},
    {knightAlive		,0},
    {whitewalkersDead  			,0},
    {knightDead	  	,0},
    {whitekingEaten 	,0}]),

  % Create ScreenFrame
  ScreenFrame = wxFrame:new(Server, -1, "Westeros", [{size,?SCREEN_SIZE}]),

  % Create ScreenPanel
  ScreenPanel = wxPanel:new(ScreenFrame,[{style, ?wxFULL_REPAINT_ON_RESIZE}]),

  % Create ScreenPopup
  ScreenPopup = setPopupMenu(),

  % Create ScreenBar
  ScreenBar = wxMenuBar:new(),
  wxFrame:setMenuBar(ScreenFrame, ScreenBar),

  % Create Status bar
  wxFrame:createStatusBar(ScreenFrame),

  % Connect left_down events
  wxFrame:connect(ScreenPanel, left_down),

  % Connect right_up events
  wxFrame:connect(ScreenPanel, right_up),

  % Set background colour
  wxWindow:setBackgroundColour(ScreenFrame, ?BACKGROUND_COLOR),

  % Set frame
  wxFrame:show(ScreenFrame),

  % Dragon cursor image
  CursorDragon = wxImage:new("Images/Cursors/Dragon.png"),
  CursorD = wxCursor:new(CursorDragon),
  
  % Knight cursor image
  CursorKnight = wxImage:new("Images/Cursors/Knight.png"),
  CursorF = wxCursor:new(CursorKnight),

  % Whiteking cursor image
  CursorWhiteking = wxImage:new("Images/Cursors/Whiteking.png"),
  CursorSW = wxCursor:new(CursorWhiteking),

  % Terminate screen cursor image
  %CursorTerminate = wxImage:new("Images/Cursors/Terminate.png"),
  %CursorT = wxCursor:new(CursorTerminate),

  % WX server state
  State = #state{ panel	 	 			= ScreenPanel,
    frame     			= ScreenFrame,
    self       			= self(),
    menu       			= ScreenPopup,
    selectedObject   	= "Knight",
    monitor    			= ScreensMonitor,
    cursorKnight  		= CursorF,
    cursorWhiteking  	= CursorSW,
    cursorDragon  		= CursorD
    %cursorTerminate 			= CursorT
	},

  % Background Image
  ImageOfBackground = wxImage:new("Images/Background/Westeros.jpg"),

  % Print callback function
  CallBackPaint =	fun(#wx{event = #wxPaint{}}, _wxObj)->
    % Creating a paint buffer
    ScreenPainter  = wxBufferedPaintDC:new(ScreenPanel),
    ImageBitmap = wxBitmap:new(ImageOfBackground),
    wxDC:drawBitmap(ScreenPainter,ImageBitmap,{0,0}),
    wxBitmap:destroy(ImageBitmap),

    String = lists:flatten(io_lib:format(" Westeros Information   --->
    Whitewalkers in westeros: ~p,
    Knight in westeros: ~p,
    Dead whitewalkers: ~p,
    Dead knight: ~p,
    Whiteking Eaten: ~p.",
      [ets:lookup_element(info, whitewalkersAlive	 , 2),
        ets:lookup_element(info, knightAlive , 2),
        ets:lookup_element(info, whitewalkersDead	 , 2),
        ets:lookup_element(info, knightDead	 , 2),
        ets:lookup_element(info, whitekingEaten , 2)])),

    % Updating the status bar with the game info
    wxFrame:setStatusText(ScreenFrame, String),
    drawEtsTable(ScreenPainter),
    wxBufferedPaintDC:destroy(ScreenPainter) end,

  wxFrame:connect(ScreenPanel, paint, [{callback, CallBackPaint}]),

  % Self messaging timer
  timer:send_interval(?SCREEN_REFRESH_TIME, self(), objectGraphicUpdate),
  {ScreenPanel, State}.


% =================================================================================
% Handlers Functions: handle_event, handle_info, handle_call, handle_cast, code_change
% =================================================================================

% ===== handle_event - open popup menu at right mouse click =====
% ===== handle_event - update "selectedObject" to the selected object =====
% ===== handle_event - wx close =====
% ===== handle_event - radiobox selected =====
handle_event(#wx{obj = ScreenPanel, event = #wxMouse{type = right_up}}, State = #state{menu = Menu}) ->
  wx:batch(fun() -> wxWindow:popupMenu(ScreenPanel, Menu) end),
  {noreply, State};

handle_event(#wx{obj = Menu, id = Id, event = #wxCommand{type = command_menu_selected}}, State = #state{}) ->
  Label = wxMenu:getLabel(Menu, Id),
  {noreply, State#state{selectedObject = Label}};

handle_event(#wx{event = #wxClose{}}, State = #state{}) ->
  io:format(" *** wx_server close *** ~n"),
  {noreply,State};

handle_event(#wx{event = #wxCommand{type = command_radiobox_selected}}, State = #state{}) ->
  {noreply,State};

% ===== event handler of left mouse click =====
handle_event(#wx{event = #wxMouse{type = left_down, x=X,y=Y}}, State = #state{}) ->
  Server = getNameOfNode({X,Y}),
  io:format("Server is:~p~n", [Server]),
  case State#state.selectedObject of
    "Knight" 		 		 -> square_server:addKnight(	Server,
      erlang:list_to_atom(erlang:ref_to_list(make_ref())),
      {X, Y},
      {X, Y},
      ?KNIGHT_TIMEOUT_FOOD,
      false);

    "Dragon" 	 		 -> square_server:addDragon(Server,
      erlang:list_to_atom(erlang:ref_to_list(make_ref())),
      {X, Y},
      {X, Y},
      ?DRAGON_TIMEOUT_FOOD,
      false);

    "Whiteking" 		 ->

      case ets:lookup(objects,theKnightKing) of
        [ELSE] -> case getNameOfNode(element(2,element(2,ELSE))) of
                    Server -> ok;
                    _Else -> whiteking:kill(theKnightKing),%square_server:delete(_Else, theKnightKing, kill),
                      global:unregister_name(theKnightKing),
                      io:fwrite("why am i herer ~n" , [])
                    end;
        _ANY -> io:fwrite(" i herer ~n" , []),ok
      end,

      square_server:addWhiteking(Server, theKnightKing,{X, Y}), %Ref = erlang:list_to_atom(erlang:ref_to_list(make_ref()))%
      ets:insert(objects, [{theKnightKing,{whiteking,{X,Y}},x,x}]);%theKnightKing is instead of Ref

    "Terminate"	 		 -> case Server of
                           ?LU ->	ConnectionGifPosition = ?LU_CONNECTION_IMAGE_POSITION;
                           ?LD ->	ConnectionGifPosition = ?LD_CONNECTION_IMAGE_POSITION;
                           ?RU ->	ConnectionGifPosition = ?RU_CONNECTION_IMAGE_POSITION;
                           ?RD ->	ConnectionGifPosition = ?RD_CONNECTION_IMAGE_POSITION
                         end,
      ets:insert(objects, {Server,{connectionImage,ConnectionGifPosition},x,x}),
      % Normal crush - monitor will restart the server
      square_server:crush(Server,normal)

  end,
  {noreply,State}.

% ===== handle_info - Get popup menu selection and change cursor =====
handle_info(objectGraphicUpdate,State)->
  case State#state.selectedObject of
    "Knight" 		 					-> wx_misc:setCursor(State#state.cursorKnight);
    "Dragon"	 		 		-> wx_misc:setCursor(State#state.cursorDragon);
    "Whiteking" 		 			-> wx_misc:setCursor(State#state.cursorWhiteking)
  end,
  screenGraphicUpdateETS(ets:tab2list(objects)),
  wxWindow:refresh(State#state.panel,[{eraseBackground,false}]),
  {noreply,State}.

% ===== handle_call - stop =====
handle_call(_Msg, _From, State) ->
  {stop, normal, ok, State}.

% ===== handle_cast - update object position, delete objects in screen =====
% ===== handle_cast - delete objects in quarter =====
% ===== handle_cast - delete connection gif =====
% ===== handle_cast - Add whitekings =====
handle_cast({etsTableUpdate, ListOfEntries ,RemoveObjects},State) ->
  %spawn(fun() -> lists:foreach(fun({Object,delete}) -> removeObjectFromSmallEts(Object) end, RemoveObjects) end),
  spawn(fun() -> lists:foreach(fun({Object,delete}) -> removeObjectFromSmallEts(Object) end, RemoveObjects),etsWxTableUpdate(ListOfEntries)  end),
  %spawn(fun() -> lists:foreach(fun({Object,delete}) -> removeObject(Object)  end, RemoveObjects) end),
  %lists:foreach(fun({Object,delete}) -> removeObjectFromSmallEts(Object) end, RemoveObjects),  
  {noreply,State};

handle_cast({removeQuarter, Quarter},State) -> deleteQuarter(Quarter),
  {noreply,State};

handle_cast({removeConnectionStatus, Quarter}, State) -> ets:delete(objects,Quarter),
  {noreply,State};

handle_cast({addWhiteking, _ObjectID, ObjectPosition}, State) -> ets:insert(objects, [{theKnightKing,{whiteking,ObjectPosition},x,x}]), % theKnightKing = _ObjectID
  {noreply,State}.

% ===== code_change =====
code_change(_, _, State) ->
  {stop, ignore, State}.


% =================================================================================
% ETS Table Functions: drawEtsTable, 	etsWxTableUpdate, removeObject
% =================================================================================

% ===== print ETS table content by objects =====
drawEtsTable(ScreenPainter) ->
  TableOfWhiteking = qlc:q([ObjectID || {ObjectID, {TypeOfObject,_ObjectPosition} ,_State, _Direction} <- ets:table(objects), (TypeOfObject == whiteking)]),
  case qlc:eval(TableOfWhiteking) of
    [] ->  done;
    ListOfWhiteking -> lists:foreach(fun(Object) -> drawObject(ScreenPainter,Object) end, ListOfWhiteking)
  end,
  TableOfKnightAndWhitewalkers = qlc:q([ObjectID || {ObjectID, {TypeOfObject,_ObjectPosition} ,_State, _Direction} <- ets:table(objects), (TypeOfObject =/= whiteking)]),
  case qlc:eval(TableOfKnightAndWhitewalkers) of
    [] ->  done;
    ListOfKnightAndWhitewalkers -> lists:foreach(fun(Object) -> drawObject(ScreenPainter,Object) end, ListOfKnightAndWhitewalkers)
  end,
  done.

% ===== updating the objects position and info =====
etsWxTableUpdate([]) -> done;
etsWxTableUpdate( [{ObjectID,{TypeOfObject,NewPosition = {_X,_Y}, St}}|RestOfTable] ) ->
  case ets:lookup(objects, ObjectID) of
    % New Object
    [] ->
      case TypeOfObject of
        whitewalker   -> ets:insert(info,{whitewalkersAlive, 	ets:lookup_element(info, whitewalkersAlive, 2) + 1 });
        knight 		-> ets:insert(info,{knightAlive, 		ets:lookup_element(info, knightAlive, 2) + 1 });
        _Other 	-> continue
      end,
      Dir    = rightWalk,
      ObjectPosition  = NewPosition,
      Stat = walking;

    % Exist object - update stats
    [{_ID, {_TypeOfObject,Pos1} ,PState, Dir1}] ->
      case ((St =:= eating) and (PState =:= walking) and (TypeOfObject =:= knight))  of
        true -> ets:insert(info,{whitekingEaten, ets:lookup_element(info, whitekingEaten, 2) + 1 });
        false -> done
      end,
	  case ((St =:= eating) and (PState =:= walking) and (TypeOfObject =:= dragon))  of
        true -> ets:insert(info,{whitekingEaten, ets:lookup_element(info, whitekingEaten, 2) + 1 });
        false -> done
      end,
      Dir    = Dir1,
      ObjectPosition  = Pos1,
      Stat = St
  end,

  % Direction Case, left or right
  case element(1,NewPosition) < element(1,ObjectPosition) of
    true  -> Direction = leftWalk;
    false -> case element(1,NewPosition) == element(1,ObjectPosition) of
               true  -> Direction = Dir;
               false -> Direction = rightWalk
             end
  end,

  % Add object to ETS table of objects
  ets:insert(objects, {ObjectID,{TypeOfObject,NewPosition},Stat,Direction}),
  case getNameOfNode(NewPosition)  of
	?LU  -> ets:insert(luEts, {ObjectID,{TypeOfObject,NewPosition,Stat}});
    ?LD  -> ets:insert(ldEts, {ObjectID,{TypeOfObject,NewPosition,Stat}});
    ?RU  -> ets:insert(ruEts, {ObjectID,{TypeOfObject,NewPosition,Stat}});
    ?RD  -> ets:insert(rdEts, {ObjectID,{TypeOfObject,NewPosition,Stat}});
	ANY  -> io:fwrite("adding object to small ets:~p~n" ,[ANY])
  end,
  etsWxTableUpdate(RestOfTable).

% ===== delete object from the ETS table and update info =====
removeObject(Object) ->
  case ets:lookup(objects, Object) of
    [{_ID, {TypeOfObject,_ObjectPosition}, _Status, _Direction}] ->
      case TypeOfObject of
        whitewalker 		->	ets:insert(info,{whitewalkersAlive, ets:lookup_element(info, whitewalkersAlive, 2) - 1 }),
          ets:insert(info,{whitewalkersDead,  ets:lookup_element(info, whitewalkersDead, 2) + 1 });
        knight  		->	ets:insert(info,{knightAlive, ets:lookup_element(info, knightAlive, 2) - 1 }),
          ets:insert(info,{knightDead,  ets:lookup_element(info, knightDead, 2) + 1 });
        whiteking 	-> 	ok;
		dragon -> ok
      end;
    [] -> ok
  end,
  ets:delete(objects, Object).
  
removeObjectFromSmallEts(Object) ->	
case ets:lookup(objects, Object) of
    [{_ID, {_TypeOfObject,_ObjectPosition}, _Status, _Direction}] ->
		ets:delete(luEts, Object),
		ets:delete(ldEts, Object),
		ets:delete(ruEts, Object),
		ets:delete(rdEts, Object);
	%	case getNameOfNode(_ObjectPosition) of
	%		?LU  -> ets:delete(luEts, Object),
	%			io:fwrite("-----------------------lu delete:~p~n" ,[Object]);
	%		?LD  -> ets:delete(ldEts, Object),
	%			io:fwrite("-----------------------ld delete:~p~n" ,[Object]);
	%		?RU  -> ets:delete(ruEts, Object),
	%			io:fwrite("-----------------------ru delete:~p~n" ,[Object]);
	%		?RD  -> ets:delete(rdEts, Object),
	%			io:fwrite("-----------------------rd delete:~p~n" ,[Object]);
	%		ANY  -> io:fwrite("-----------------------adding object to small ets:~p~n" ,[ANY])
	 %   end;
	 _Any -> io:fwrite("any ~p~n", [Object]), ok
    %[] -> io:fwrite("----------------empty!!")
 end,
 ets:delete(objects, Object).

% =================================================================================
% Monitoring Functions: createScreenMonitor, monitorReceiveLoop
% =================================================================================

% ===== Function to create a process which monitor a screen node =====
createScreenMonitor() ->
  % Monitor the node and go to receive block
  LU = spawn( fun() -> erlang:monitor_node(?LU_NODE,true), monitorReceiveLoop(?LU_NODE) end),
  LD = spawn( fun() -> erlang:monitor_node(?LD_NODE,true), monitorReceiveLoop(?LD_NODE) end),
  RU = spawn( fun() -> erlang:monitor_node(?RU_NODE,true), monitorReceiveLoop(?RU_NODE) end),
  RD = spawn( fun() -> erlang:monitor_node(?RD_NODE,true), monitorReceiveLoop(?RD_NODE) end),
  % Register the monitor process
  register(luScreenMonitor,LU),
  register(ldScreenMonitor,LD),
  register(ruScreenMonitor,RU),
  register(rdScreenMonitor,RD).

% ===== receive block for monitor process =====
monitorReceiveLoop(Node) ->
  % Monitor receive block
  io:fwrite(" ----- 'Self': ~p is monitoring 'Node': ~p ----- ~n",[self(),Node]),
  receive
    {nodedown,Node} ->
      % Received Node Down message
      io:fwrite("Node: ~p Has crushed, repairing...~n",[Node]),
      case Node of
        ?LU_NODE -> Server = lu, Heir = rd, EtsName = luEts, _ConnectionGifPosition = ?LU_CONNECTION_IMAGE_POSITION;
        ?LD_NODE -> Server = ld, Heir = ru, EtsName = ldEts, _ConnectionGifPosition = ?LD_CONNECTION_IMAGE_POSITION;
        ?RU_NODE -> Server = ru, Heir = ld, EtsName = ruEts, _ConnectionGifPosition = ?RU_CONNECTION_IMAGE_POSITION;
        ?RD_NODE -> Server = rd, Heir = lu, EtsName = rdEts, _ConnectionGifPosition = ?RD_CONNECTION_IMAGE_POSITION
      end,
      % Delete objects in the quarter
      deleteQuarter(Server),
      ets:insert(objects, {Server,{connectionImage,_ConnectionGifPosition},x,x}),
      % Reconnect to the node
      serverReconnection(Node,Server,Heir,1,EtsName);

  % Kill monitor command
    kill 						->	io:fwrite("Monitor Terminating~n");

  % Other operations
    Other 					->	io:fwrite("Other: ~p~n",[Other]),
      monitorReceiveLoop(Node)
  end.


% =================================================================================
% Connection Functions: serverReconnection, 	deleteQuarter, deleteQuarter, 	getNameOfNode, 	terminate
% =================================================================================

% ===== serverReconnection =====
%% monitor serverReconnection function, after a time slice it reconnects again to the server and
%% restarts it when the connection established
serverReconnection(Node ,Server,Heir,X,EtsName) ->
  io:format("     SERVER RECONNECTION     ~n"),
  receive
    kill 						->	io:fwrite("Monitor Terminating~n")

  after 2000 ->
    % Try to connect the server
    case net_adm:ping(Node) of
      pong ->
        io:fwrite("Connected to ~p, trying to start Server. ~n", [Node]),
        case rpc:call(Node, compile, file, [square_server]) of
          {ok, _IP} ->
            % compile and start server
            rpc:call(Node, compile, file, [knight]),
			rpc:call(Node, compile, file, [dragon]),
            rpc:call(Node, compile, file, [whitewalker]),
            rpc:call(Node, compile, file, [whiteking]),
            rpc:call(Node, compile, file, [wx_server]),
            try rpc:call(Node, square_server, start, [Server]) of
              _ok -> ok
            catch
              exit:_ANY -> io:fwrite(" exit !!! ~n~n~n")
            end,
            % Delete connection image after connecting, monitor the node again
            ets:delete(objects, Server),
            erlang:monitor_node(Node,true),
			ets:insert(nodesNames,{Server,Server}),
			square_server:updateNodesETS(?LD,Server,Server),
			square_server:updateNodesETS(?RD,Server,Server),
			square_server:updateNodesETS(?RU,Server,Server),
			square_server:updateNodesETS(?LU,Server,Server),
			case Server  of
				?LU  -> square_server:serverReceiveLoop1(Server,ets:tab2list(luEts)),
						%io:fwrite("the list is:~p~n" ,[ets:tab2list(rdEts)]),
          _TEMPLIST = [_X || _X <- ets:tab2list(rdEts),getNameOfNode(element(2,element(2,_X))) =:= ?LU],
%%          lists:foreach(fun(Object) -> square_server:delete(?RD, ID,Object, kill) end, _TEMPLIST),
            square_server: removeBackup(?RD),
						square_server:serverReceiveLoop1(Server,_TEMPLIST),
						ets:delete_all_objects(rdEts),
						ets:delete_all_objects(luEts);
				?LD  -> square_server:serverReceiveLoop1(Server,ets:tab2list(ldEts)),
          _TEMPLIST = [_X || _X <- ets:tab2list(ruEts),getNameOfNode(element(2,element(2,_X))) =:= ?LD],
%          lists:foreach(fun(Object) -> removeObjectFromSmallEts(Object) end, _TEMPLIST),
          square_server: removeBackup(?RU),
						square_server:serverReceiveLoop1(Server,_TEMPLIST),
						ets:delete_all_objects(ruEts),
						ets:delete_all_objects(ldEts);
				?RU  -> square_server:serverReceiveLoop1(Server,ets:tab2list(ruEts)),
          _TEMPLIST = [_X || _X <- ets:tab2list(ldEts),getNameOfNode(element(2,element(2,_X))) =:= ?RU],
 %         lists:foreach(fun(Object) -> removeObjectFromSmallEts(Object) end, _TEMPLIST),
          square_server: removeBackup(?LD),
						square_server:serverReceiveLoop1(Server,_TEMPLIST),
						ets:delete_all_objects(ldEts),
						ets:delete_all_objects(ruEts);
				?RD  -> square_server:serverReceiveLoop1(Server,ets:tab2list(rdEts)),
          _TEMPLIST = [_X || _X <- ets:tab2list(luEts),getNameOfNode(element(2,element(2,_X))) =:= ?RD],
  %        lists:foreach(fun(Object) -> removeObjectFromSmallEts(Object) end, _TEMPLIST),
          square_server: removeBackup(?LU),
						square_server:serverReceiveLoop1(Server,_TEMPLIST),
						ets:delete_all_objects(luEts),
						ets:delete_all_objects(rdEts);
				ANY  -> io:fwrite("calling square server recovery:~p~n" ,[ANY])
			end, 
            monitorReceiveLoop(Node);

          % Restart Failed
          _ELSE 	  -> 	io:fwrite("~p Server Start Failure!~n", [Node]),
            serverReconnection(Node, Server,Heir,X+1,EtsName)
        end;

      % server is not responding to connection
      pang ->
        io:format("Cannot complete connection to node: ~p.~n",[Node]),
		case X of
			3 ->
        ets:delete(objects, Server),
        ets:insert(nodesNames,{Server,Heir}),
        square_server:updateNodesETS(?LD,Heir,Server),
        square_server:updateNodesETS(?RD,Heir,Server),
        square_server:updateNodesETS(?RU,Heir,Server),
        square_server:updateNodesETS(?LU,Heir,Server),
				 square_server:serverReceiveLoop1(Heir,ets:tab2list(EtsName)),
        io:format("the list of the fallen one is: ~p.~n",[ets:tab2list(EtsName)]),
				 ets:delete_all_objects(EtsName),
        io:format("the list of the fallen one is: ~p.~n",[ets:tab2list(EtsName)]),
				 io:format("X: ~p, Server: ~p, Heir: ~p, EtsName: ~p  .~n",[X,Server,Heir,EtsName]),
				 serverReconnection(Node, Server,Heir,X+1,EtsName);
			4 -> serverReconnection(Node, Server,Heir,X,EtsName);
			_ANY -> serverReconnection(Node, Server,Heir,X+1,EtsName)
		end
	end
  end.

% ===== delete all objects in a given quarter screen =====
deleteQuarter(Server) ->
  io:format("Deleteing quarter~n"),
  TableOfObjects = qlc:q([ObjectID || {ObjectID, {TypeOfObject,{X,Y}} ,_PState, _Dir1} <- ets:table(objects),
    (getNameOfNode({X,Y}) =:= Server) and (TypeOfObject =/= connectionImage)]),
  case qlc:eval(TableOfObjects) of
    [] ->  done;
    List -> lists:foreach(fun(Object) -> removeObject(Object) end, List)
  end.

% ===== returns a nodes name according to X,Y position =====
getNameOfNode({X,Y}) ->
  case {X > ?X_MAXVALUE/2, (Y > ?Y_MAXVALUE/2)} of
    {false, false} -> ets:lookup_element(nodesNames,lu,2);
    {false, true}  -> ets:lookup_element(nodesNames,ld,2);
    {true, false}  -> ets:lookup_element(nodesNames,ru,2);
    {true, true}   -> ets:lookup_element(nodesNames,rd,2)
  end.

% ===== Terminate all screens, monitors and wx destory =====
terminate(_Reason, State) ->
  square_server:crush(ets:lookup_element(nodesNames,lu,2),shutdown),
  square_server:crush(ets:lookup_element(nodesNames,ld,2),shutdown),
  square_server:crush(ets:lookup_element(nodesNames,ru,2),shutdown),
  square_server:crush(ets:lookup_element(nodesNames,rd,2),shutdown),
  whereis(luScreenMonitor) ! kill,
  whereis(ldScreenMonitor) ! kill,
  whereis(ruScreenMonitor) ! kill,
  whereis(rdScreenMonitor) ! kill,
  wxPanel:destroy(State#state.panel),
  wx:destroy(),
  io:fwrite("   Termination !!! ~n~n"),
  done.


% =================================================================================
% Graphical Functions: drawObject, setPopupMenu, screenGraphicUpdateETS
% =================================================================================

% ===== Function to draw each ETS entry =====
drawObject(ScreenPainter,Object) ->
  case ets:lookup(objects, Object) of
    [] -> ok;
    [{_ID, {TypeOfObject, {X,Y} = _ObjectPosition}, Status, Direction}] ->
      case {TypeOfObject, Status, Direction} of
        % Knight walking - Left Image
        {knight, walking, leftWalk}        ->	Image = wxImage:new("Images/knight/KnightWalkLeft.png");
        % Knight walking - Right Image
        {knight, walking, rightWalk}       ->  Image = wxImage:new("Images/knight/KnightWalkRight.png");
		% Dragon walking - Left Image
        {dragon, walking, leftWalk}        ->	Image = wxImage:new("Images/dragon/DragonLeft.png");
        % Dragon walking - Right Image
        {dragon, walking, rightWalk}       ->  Image = wxImage:new("Images/dragon/DragonRight.png");
        % Whitewalker walking - Left Image
        {whitewalker, walking, leftWalk} 	    ->	Image = wxImage:new("Images/whitewalker/WhitewalkerWalkLeft.png");
        % Whitewalker walking - Right Image
        {whitewalker, walking, rightWalk} 	    ->	Image = wxImage:new("Images/whitewalker/WhitewalkerWalkRight.png");
        % Knight escaping - Left Image
        {knight, escaping, leftWalk}        ->  Image = wxImage:new("Images/knight/KnightEscapeLeft.png");
        % Knight escaping - Right Image
        {knight, escaping, rightWalk}       ->  Image = wxImage:new("Images/knight/KnightEscapeRight.png");
        % Whitewalker chasing - Left Image
        {whitewalker, chasing, leftWalk} 	 	    ->  Image = wxImage:new("Images/whitewalker/WhitewalkerChaseLeft.png");
        % Whitewalker chasing - Right Image
        {whitewalker, chasing, rightWalk} 	    ->  Image = wxImage:new("Images/whitewalker/WhitewalkerChaseRight.png");
        % Knight is eating whiteking - Image
        {knight,eating,_}                   ->  Image = wxImage:new("Images/knight/KnightEating.png");
		% Dragon is eating whiteking - Image
        {dragon,eating,_}                   ->  Image = wxImage:new("Images/dragon/DragonEating.png");
        % Whitewalker is eating a knight - Image
        {whitewalker,eating,_} 		              ->  Image = wxImage:new("Images/whitewalker/WhitewalkerEating.png");
        % Connection lost Image States
        {connectionImage,_,_} 		        ->  Image = wxImage:new("Images/Connection/ConnectImage.png");
        % If neither knight nor whitewalker then pick Whiteking picture
        _Whiteking	                        ->  Image = wxImage:new("Images/whiteking/Whiteking.png")
      end,

      % Get ImageBitmap of the Image
      ImageBitmap = wxBitmap:new(Image),

      % Destroy the Image
      wxImage:destroy(Image),

      % Draw in the mouse click position
      wxDC:drawBitmap(ScreenPainter, ImageBitmap, {X,Y}),

      % Destroy the ImageBitmap
      wxBitmap:destroy(ImageBitmap)
  end.

% ===== Function to draw popup menu =====
setPopupMenu() ->
  io:format("POPUP menu~n"),
  PopupMenu = wxMenu:new([]),
  %PopupSubMenu1  = wxMenu:new([]),
  %PopupSubMenu2 = wxMenu:new([]),

  wxMenuItem:enable(wxMenu:append(PopupMenu, ?wxID_ANY, "Place object", []), [{enable,false}]),
  wxMenu:appendSeparator(PopupMenu),

  % Whiteking popup menu button
  WhitekingImage  = wxImage:new("Images/Cursors/Whiteking.png"),
  WhitekingBitmap = wxBitmap:new(WhitekingImage),
  Whiteking = wxMenuItem:new([{parentMenu, PopupMenu},
    {id, ?wxID_ANY},
    {text, "Whiteking"},
    {kind, ?wxITEM_NORMAL}]),
  wxImage:destroy(WhitekingImage),
  wxMenuItem:setBitmap(Whiteking, WhitekingBitmap),
  wxBitmap:destroy(WhitekingBitmap),
  wxMenu:append(PopupMenu, Whiteking),

  % Whitewalker popup menu button
  DragonImage  = wxImage:new("Images/Cursors/Dragon.png"),
  DragonBitmap = wxBitmap:new(DragonImage),
  Dragon = wxMenuItem:new([{parentMenu, PopupMenu},
    {id, ?wxID_ANY},
    {text, "Dragon"},
    {kind, ?wxITEM_NORMAL}]),
  wxImage:destroy(DragonImage),
  wxMenuItem:setBitmap(Dragon, DragonBitmap),
  wxBitmap:destroy(DragonBitmap),
  wxMenu:append(PopupMenu, Dragon),

  % Knight popup menu button
  KnightImage  = wxImage:new("Images/Cursors/Knight.png"),
  KnightBitmap = wxBitmap:new(KnightImage),
  Knight = wxMenuItem:new([{parentMenu, PopupMenu},
    {id, ?wxID_ANY},
    {text, "Knight"},
    {kind, ?wxITEM_NORMAL}]),
  wxImage:destroy(KnightImage),
  wxMenuItem:setBitmap(Knight, KnightBitmap),
  wxBitmap:destroy(KnightBitmap),
  wxMenu:append(PopupMenu, Knight),

  % Terminate popup menu button
  %TerminateImage  = wxImage:new("Images/Cursors/Terminate.png"),
  %TerminateBitmap = wxBitmap:new(TerminateImage),
  %Terminate = wxMenuItem:new([{parentMenu, PopupMenu},
  %  {id, ?wxID_ANY},
  %  {text, "Terminate"},
  %  {kind, ?wxITEM_NORMAL}]),
  %wxImage:destroy(TerminateImage),
  %wxMenuItem:setBitmap(Terminate, TerminateBitmap),
  %wxBitmap:destroy(TerminateBitmap),
  %wxMenu:append(PopupMenu, Terminate),

  % connect popup menu to event
  wxMenu:connect(PopupMenu, command_menu_selected),
  PopupMenu.

% ===== Update every entry in ETS table with the next image =====
screenGraphicUpdateETS([]) ->	0;
screenGraphicUpdateETS([{ObjectID, {_TypeOfObject, _ObjectPosition}, _Status, _Direction}|RestOfEntries]) ->
  ets:insert(objects, {ObjectID, {_TypeOfObject,_ObjectPosition}, _Status, _Direction}),
  screenGraphicUpdateETS(RestOfEntries).
