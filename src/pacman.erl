%%
%% PacMan game ported from java applet
%%
%% (C)2000
%% Brian Postma
%% b.postma@hetnet.nl
%% http://www.homepages.hetnet.nl/~brianpostma
%%

-module(pacman).

-export([start/0, start_link/0]).
-export([run_game/0]).

-import(lists, [map/2]).

-ifdef(debug).
-define(dbg(F, A), io:format((F),(A))).
-else.
-define(dbg(F,A), ok).
-endif.

-include_lib("wx/include/wx.hrl").
-include_lib("wx/include/gl.hrl").

-define(WALL_LEFT,  16#01).
-define(WALL_ABOVE, 16#02).
-define(WALL_RIGHT, 16#04).
-define(WALL_BELOW, 16#08).
-define(FOOD_SMALL, 16#10).
-define(FOOD_BIG,   16#20).

-define(IS_WALL_LEFT(Z), (((Z) band ?WALL_LEFT) =/= 0)).
-define(IS_WALL_RIGHT(Z), (((Z) band ?WALL_RIGHT) =/= 0)).
-define(IS_WALL_ABOVE(Z), (((Z) band ?WALL_ABOVE) =/= 0)).
-define(IS_WALL_BELOW(Z), (((Z) band ?WALL_BELOW) =/= 0)).

-define(NO_WALL_LEFT(Z), (((Z) band ?WALL_LEFT) == 0)).
-define(NO_WALL_RIGHT(Z), (((Z) band ?WALL_RIGHT) == 0)).
-define(NO_WALL_ABOVE(Z), (((Z) band ?WALL_ABOVE) == 0)).
-define(NO_WALL_BELOW(Z), (((Z) band ?WALL_BELOW) == 0)).

-define(IS_FOOD_SMALL(Z), (((Z) band ?FOOD_SMALL) =/= 0)).
-define(IS_FOOD_BIG(Z),   (((Z) band ?FOOD_BIG) =/= 0)).

-record(images,
	{
	  ghost1,
	  ghost2,
	  ghostscared1,
	  ghostscared2,
	  pacman_up,
	  pacman_left,
	  pacman_right,
	  pacman_down
	 }).

%% 24 can be divided by 1 2 4 4 6 8 hence the valid speeds
-define(BlockSize, 24).      %% in pixels
-define(NBlocks,   15).      %% size of maze in positions
-define(ScreenDelay, 120).
-define(AnimDelay, 8).
-define(PacAnimDelay, 4).
-define(GhostAnimCount, 2).
-define(PacManAnimCount, 4).
-define(MaxGhosts, 12).
-define(PacManSpeed, 6).
-define(MaxScaredTime, 120).
-define(MinScaredTime, 20).
-define(MaxSpeed, 6).
-define(ValidSpeeds, {1,2,3,4,6,8}).

-define(MAX_BM_W, 256).
-define(MAX_BM_H, 64).

-define(CoordToPos(X,Y),
	(((X) div ?BlockSize) + ?NBlocks*((Y) div ?BlockSize)) ).
-define(XToLoc(X), ((X) rem ?BlockSize)).
-define(YToLoc(Y), ((Y) rem ?BlockSize)).
-define(LocToPos(I, J), ((I) + ?NBlocks*(J))).  %% I=column J=row

-define(PosToX(Pos), ( ((Pos) rem ?NBlocks)*?BlockSize)).
-define(PosToY(Pos), ( ((Pos) div ?NBlocks)*?BlockSize)).
-define(PosToCoord(Pos), { ?PosToX(Pos), ?PosToY(Pos)}).


-record(ghost,
	{
	  x=0,
	  y=0,
	  dx=1,
	  dy=1,
	  speed=0
	 }).

-record(pacman,
	{
	  x  = 0,
	  y  = 0,
	  dx = 1,
	  dy = 1
	}).


-record(game,
	{
	  panel,           %% GL Panel
	  goff,            %% offscreem pixmap
	  fid,             %% Font TextureID
	  win,             %% window
	  width,           %% screem width
	  height,          %% screen height

	  images,          %% #images {}

	  font,            

	  dotcolor      = {255,192,192,255},
	  bigdotcolor   = 192,
	  dbigdotcolor  = -2,
	  mazecolor     = {255,32,192,255},

	  quit          = false,
	  ingame        = false,
	  showtitle     = true,
	  scared        = false,
	  dying         = false,

	  animcount     = 8,
	  pacanimcount  = 2,
	  pacanimdir    = 1,
	  count         = 120,
	  ghostanimpos  = 0,
	  pacmananimpos = 0,
	  nrofghosts    = 6,
	  pacsleft,
	  score,
	  deathcounter,

	  ghosts,         %% [ #ghost {} [ nrofghosts
	  pacman,         %% #pacman

	  reqdx,
	  reqdy,
	  viewdx,
	  viewdy,

	  scaredcount,
	  scaredtime,

	  currentspeed=3,     %% 1,2,3,4,5,6
	  maze
	 }).

start() ->
    application:start(pacman).

start_link() ->
    {ok,proc_lib:spawn_link(?MODULE, run_game, [])}.

run_game() ->
    try
	game_loop(init())
    catch _:Reason ->
	    io:format("CRASH ~p: ~p~n",[Reason, erlang:get_stacktrace()]),
	    error
    end.

game_loop(G) when G#game.quit == true ->
    final(G);
game_loop(G) ->
    T0 = now_milli(),
    G1 = wx:batch(fun() -> paint(G) end),
    T1 = now_milli(),
    T = (T0+40)-T1,
    if T =< 0 ->
	    game_loop(check_input(G1));
       true ->
	    wx_misc:getKeyState(?WXK_LEFT),
	    receive
	    after T ->
		    %% Sync driver thread
		    game_loop(check_input(G1))
	    end
    end.

%% poll all key events
check_input(G) ->
    receive
	#wx{event=#wxClose{}} ->
	    G#game { quit = true };
	#wx{event=#wxKey{type=key_down, keyCode=Sym}} ->
	    check_input(key_down(Sym, G));
	#wx{event=#wxKey{type=key_up, keyCode=Sym}} ->
	    check_input(key_up(Sym, G));
	Got ->
	    io:format("Got ~p~n",[Got]),
	    G
    after 0 ->
	    G
    end.

key_down(Key, G) when G#game.ingame == false ->
    if Key == $s; Key == $S ->
	    game_init(G#game { ingame = true });
       Key == $q; Key == $Q ->
	    G#game { quit = true };
       true ->
	    G
    end;
key_down(Key, G) when G#game.ingame == true ->
    case Key of
	27 ->    G#game { ingame = false };
	$q   ->  G#game { quit = true };
	$Q   ->  G#game { quit = true };
	?WXK_LEFT  -> G#game { reqdx = -1, reqdy = 0 };
	?WXK_RIGHT -> G#game { reqdx = 1,  reqdy = 0 };
	?WXK_UP ->    G#game { reqdx = 0,  reqdy = 1 };
	?WXK_DOWN ->  G#game { reqdx = 0,  reqdy = -1 };
	_ ->
	    G
    end;
key_down(_, G) ->
    G.

key_up(_Key, G) ->
    if %% Key == ?WXK_LEFT;
       %% Key == ?WXK_RIGHT;
       %% Key == ?WXK_DOWN;
       %% Key == ?WXK_UP ->
       %% 	    G#game { reqdx = 0, reqdy = 0};
       true ->
	    G
    end.

now_milli() ->
    {M,S,Us} = os:timestamp(),
    1000*(M*1000000+S)+(Us div 1000).


load_image(FileName) ->
    PathName = filename:join(code:priv_dir(pacman), FileName),
    {Data, Format} = get_data_for_use_with_teximage2d(PathName),
    32*32*4 = size(Data),
    [TId] = gl:genTextures(1),
    gl:bindTexture(?GL_TEXTURE_2D, TId),
    gl:texParameteri(?GL_TEXTURE_2D, ?GL_TEXTURE_MAG_FILTER, ?GL_NEAREST),
    gl:texParameteri(?GL_TEXTURE_2D, ?GL_TEXTURE_MIN_FILTER, ?GL_NEAREST),
    gl:texImage2D(?GL_TEXTURE_2D, 0, Format, 32, 32, 0, Format, ?GL_UNSIGNED_BYTE, Data),
    TId.


load_directions(FileName) ->
    Tid = load_image(FileName),
    {{180, Tid}, {0, Tid}, {90, Tid}, {270, Tid}}.

load_images() ->
    {R2,L2,U2,D2} = load_directions("PacMan2.png"),
    {R3,L3,U3,D3} = load_directions("PacMan3.png"),
    {R4,L4,U4,D4} = load_directions("PacMan4.png"),
    P = load_image("PacMan1.png"),

    #images {
	      ghost1=load_image("Ghost1.png"),
	      ghost2=load_image("Ghost2.png"),
	      ghostscared1=load_image("GhostScared1.png"),
	      ghostscared2=load_image("GhostScared2.png"),

	      pacman_left  = {P,L2,L3,L4},
	      pacman_right = {P,R2,R3,R4},
	      pacman_up    = {P,U2,U3,U4},
	      pacman_down  = {P,D2,D3,D4}
	    }.

get_data_for_use_with_teximage2d(PathName) ->
    Image = wxImage:new(PathName),
    Format = case wxImage:hasAlpha(Image) of
		 true  -> ?GL_RGBA;
		 false ->
		     true = wxImage:hasMask(Image),
		     wxImage:initAlpha(Image),
		     ?GL_RGBA
	     end,
    22 = wxImage:getWidth(Image),
    22 = wxImage:getHeight(Image),
    RGB = wxImage:getData(Image),
    Alpha = wxImage:getAlpha(Image),
    RBGA = interleave_rgb_and_alpha(RGB, Alpha),
    PadSize = (32*4 - 22*4)*8,
    RBGAPadded = << <<Bin/binary, 0:PadSize>> || <<Bin:(22*4)/binary>> <= RBGA>>,
    PadRows = (32-22)*32*4*8,
    {<<RBGAPadded/binary, 0:PadRows>>, Format}.

interleave_rgb_and_alpha(RGB, Alpha) ->
    list_to_binary(
      lists:zipwith(fun({R, G, B}, A) ->
			    <<R, G, B, A>>
		    end,
		    [{R,G,B} || <<R, G, B>> <= RGB],
		    [A || <<A>> <= Alpha])).


draw_text(#game{goff=Bmp, fid=Fid, font=Font}, {X,Y}, String, {R,G,B}) ->
    DC = wxMemoryDC:new(Bmp),
    wxMemoryDC:setFont(DC, Font),
    wxMemoryDC:setBackground(DC, ?wxBLACK_BRUSH),
    wxMemoryDC:clear(DC),
    wxMemoryDC:setTextForeground(DC, {255, 255, 255}),
    wxMemoryDC:drawText(DC, String, {0,0}),
    {StrW0, StrH0} = wxDC:getTextExtent(DC, String),
    StrW = min(StrW0, ?MAX_BM_W),
    StrH = min(StrH0, ?MAX_BM_H),
    Img   = wxBitmap:convertToImage(Bmp),
    Alpha = wxImage:getData(Img),
    wxMemoryDC:destroy(DC),
    wxImage:destroy(Img),
    RGBA = << <<R:8,G:8,B:8,A:8>> || <<A:8,_:8,_:8>> <= Alpha >>,
    gl:bindTexture(?GL_TEXTURE_2D, Fid),
    gl:texImage2D(?GL_TEXTURE_2D, 0, ?GL_RGBA, ?MAX_BM_W, ?MAX_BM_H, 0, 
		  ?GL_RGBA, ?GL_UNSIGNED_BYTE, RGBA),
    gl:enable(?GL_TEXTURE_2D),
    gl:'begin'(?GL_QUADS),
    MaxX = StrW / ?MAX_BM_W,
    MaxY = StrH / ?MAX_BM_H,
    gl:texCoord2f(0.0, MaxY), gl:vertex2i(X,     Y),
    gl:texCoord2f(MaxX,  MaxY), gl:vertex2i(X+StrW,Y),
    gl:texCoord2f(MaxX,  0.0),  gl:vertex2i(X+StrW,Y+StrH),
    gl:texCoord2f(0.0, 0.0),  gl:vertex2i(X,     Y+StrH),
    gl:'end'(),
    gl:disable(?GL_TEXTURE_2D).

final(G) ->
    wxFrame:destroy(G#game.win),
    ok.

init() ->
    wx:new(),
    Width  = ?BlockSize*?NBlocks,
    Height = (?BlockSize+1)*?NBlocks,
    Win    = wxFrame:new(wx:null(), -1, "Pacman", [{size, {Width+20, Height+100}}]),
    Panel  = wxGLCanvas:new(Win, [{size, {Width+20, Height+100}},
				  {attribList, [?WX_GL_RGBA,?WX_GL_DOUBLEBUFFER,0]}]),

    wxPanel:connect(Panel, key_down),
    wxPanel:connect(Panel, key_up),
    wxFrame:connect(Win,   close_window, [{skip, false}]),
    wxFrame:show(Win),
    wxGLCanvas:setCurrent(Panel),
    wxGLCanvas:setFocus(Panel),
    {W,H} = wxWindow:getClientSize(Panel),
    gl:viewport(5,5,W-5,H-5),
    gl:matrixMode(?GL_PROJECTION),
    gl:loadIdentity(),
    glu:ortho2D(-1.0, W, -1.0, H),
    gl:enable(?GL_BLEND),
    gl:blendFunc(?GL_SRC_ALPHA, ?GL_ONE_MINUS_SRC_ALPHA),
    gl:matrixMode(?GL_MODELVIEW),
    [Fid] = gl:genTextures(1),
    gl:bindTexture(?GL_TEXTURE_2D, Fid),
    gl:texParameteri(?GL_TEXTURE_2D, ?GL_TEXTURE_MAG_FILTER, ?GL_LINEAR),
    gl:texParameteri(?GL_TEXTURE_2D, ?GL_TEXTURE_MIN_FILTER, ?GL_LINEAR),
    gl:texEnvf(?GL_TEXTURE_ENV, ?GL_TEXTURE_ENV_MODE, ?GL_REPLACE),

    Font = wxFont:new(24, ?wxFONTFAMILY_DEFAULT, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_BOLD),
    G = #game {  win    = Win,
		 panel  = Panel,
		 goff   = wxBitmap:new(?MAX_BM_W, ?MAX_BM_H),
		 fid    = Fid,
		 font   = Font,
		 width  = Width,
		 height = Height,
		 images = load_images(),
		 maze   = {},
		 ghosts = [],
		 pacman = #pacman {}
		},
    game_init(G).


game_init(G) ->
    G1 = G#game { pacsleft   = 3,
		  score      = 0,
		  scaredtime = ?MaxScaredTime
		 },
    G2 = level_init(G1),
    G2#game { nrofghosts   = 6,
	      currentspeed = 3,
	      scaredcount = 0,
	      scaredtime   = ?MaxScaredTime
	     }.

level_init(G) ->
    G1 = G#game { maze = level1data() },
    level_continue(G1).

level_continue(G) ->
    CurrentSpeed = G#game.currentspeed,
    NrOfGhosts   = G#game.nrofghosts,

    Ghost = map(fun(I) ->
			Random = random:uniform(CurrentSpeed),
			Speed  = element(Random,?ValidSpeeds),
			#ghost { y  = 7*?BlockSize,
				 x  = 7*?BlockSize,
				 dy = 0,
				 dx = 2*(I band 1) - 1,
				 speed=Speed
				}
		end, lists:seq(1, NrOfGhosts)),
    Maze0 = G#game.maze,
    Maze1 = set_maze_loc(6, 7, Maze0, ?WALL_ABOVE bor ?WALL_BELOW),
    Maze2 = set_maze_loc(8, 7, Maze1, ?WALL_ABOVE bor ?WALL_BELOW),

    G#game { ghosts = Ghost,
	     maze = Maze2,
	     pacman = #pacman { x = 7*?BlockSize,
				y = 11*?BlockSize,
				dx = 0,
				dy = 0 },
	     reqdx   = 0,
	     reqdy   = 0,
	     viewdx  = -1,
	     viewdy  = 0,
	     dying   = false,
	     scared  = false }.


paint(G) ->
    Panel = G#game.panel,
    gl:clear(?GL_COLOR_BUFFER_BIT bor ?GL_DEPTH_BUFFER_BIT),
    G1 = draw_maze(G),
    G2 = draw_score(G1),
    G3 = do_anim(G2),
    G4 = if G3#game.ingame == true ->
		 play_game(G3);
	    true ->
		 play_demo(G3)
	 end,
    wxGLCanvas:swapBuffers(Panel),
    G4.

draw_maze(G) ->
    BSz       = ?BlockSize-1,
    Maze      = G#game.maze,
    MazeColor = G#game.mazecolor,
    DotColor  = G#game.dotcolor,
    BigDotColor = G#game.bigdotcolor + G#game.dbigdotcolor,
    DBigDotColor = if BigDotColor =< 64;
		      BigDotColor >= 192 ->
			   -G#game.dbigdotcolor;
		      true ->
			   G#game.dbigdotcolor
		   end,
    each(0, size(Maze)-1,
	 fun(I) ->
		 X = ?PosToX(I),
		 Y = ?PosToY(I),
		 Z = get_maze_pos(I,Maze),
		 gl:'begin'(?GL_LINES),
		 gl:color4ubv(MazeColor),
		 if ?IS_WALL_LEFT(Z) ->
			 gl:vertex2d(X,Y), gl:vertex2d(X,Y+BSz);
		    true -> ok
		 end,
		 if ?IS_WALL_ABOVE(Z) ->
			 gl:vertex2d(X,Y), gl:vertex2d(X+BSz,Y);
		    true -> ok
		 end,
		 if ?IS_WALL_RIGHT(Z) ->
			 gl:vertex2d(X+BSz,Y), gl:vertex2d(X+BSz,Y+BSz);
		    true -> ok
		 end,
		 if ?IS_WALL_BELOW(Z) ->
			 gl:vertex2d(X,Y+BSz), gl:vertex2d(X+BSz,Y+BSz);
		    true -> ok
		 end,
		 gl:'end'(),
		 gl:'begin'(?GL_QUADS),
		 if ?IS_FOOD_SMALL(Z) ->
			 gl:color4ubv(DotColor),
			 gl:vertex2d(X+11,Y+11), gl:vertex2d(X+13,Y+11),
			 gl:vertex2d(X+13,Y+13), gl:vertex2d(X+11,Y+13);
		    true -> ok
		 end,
		 if ?IS_FOOD_BIG(Z) ->
			 gl:color4ubv({255,224,224-BigDotColor,BigDotColor}),
			 gl:vertex2d(X+8,Y+8), gl:vertex2d(X+16,Y+8),
			 gl:vertex2d(X+16,Y+16), gl:vertex2d(X+8,Y+16);
		    true -> ok
		 end,
		 gl:'end'(),
		 ok
	 end),
    G#game { bigdotcolor = BigDotColor,
	     dbigdotcolor = DBigDotColor }.

draw_score(G) ->
    Image = G#game.images,
    each(0, G#game.pacsleft-1,
	 fun(I) ->
		 draw_image(element(3, Image#images.pacman_left),
			    I*28+8, G#game.height-1)
	 end),
    draw_text(G, {G#game.width div 2 - 30, G#game.height-8},
	      io_lib:format("Score: ~.4.0w", [G#game.score]), {250, 250, 0}),
    G.


do_anim(G) ->
    AnimCount0 = G#game.animcount - 1,
    AnimCount  = if AnimCount0 =< 0 ->
			 ?AnimDelay;
		    true ->
			 AnimCount0
		 end,
    GhostAnimPos = if AnimCount0 =< 0  ->
			   (G#game.ghostanimpos + 1) rem ?GhostAnimCount;
		      true ->
			   G#game.ghostanimpos
		   end,

    if G#game.pacanimcount =< 1 ->
	    PacmanAnimPos = G#game.pacmananimpos+G#game.pacanimdir,
	    PacAnimDir = bounce(PacmanAnimPos,0,?PacManAnimCount-1,
				G#game.pacanimdir),
	    G#game { animcount     = AnimCount,
		     ghostanimpos  = GhostAnimPos,
		     pacanimcount  = ?PacAnimDelay,
		     pacmananimpos = PacmanAnimPos,
		     pacanimdir    = PacAnimDir };
       true ->
	    G#game { animcount     = AnimCount,
		     ghostanimpos  = GhostAnimPos,
		     pacanimcount  = G#game.pacanimcount - 1
		   }
    end.

play_game(G) ->
    case G#game.dying of
	true ->
	    death(G);
	false ->
	    G1 = check_scared(G),
	    G2 = move_pacman(G1),
	    draw_pacman(G2),
	    G3 = move_ghosts(G2),
	    check_maze(G3)
    end.

play_demo(G) ->
    G1 = check_scared(G),
    G2 = move_ghosts(G1),
    show_intro_screen(G2).

check_scared(G) ->
    ScaredCount = G#game.scaredcount-1,
    Scared = if ScaredCount =< 0 ->
		     false;
		true -> G#game.scared
	     end,
    MazeColor = if Scared == true, ScaredCount >= 30 ->
			{255,192,32,255};
		   true ->
			{255,32,192,255}
		end,
    Maze0 = G#game.maze,
    Maze = if Scared == true ->
		   Maze1 = set_maze_loc(6, 7, Maze0,
					?WALL_ABOVE bor ?WALL_BELOW bor
					?WALL_LEFT),
		   set_maze_loc(8, 7, Maze1,
				?WALL_ABOVE bor ?WALL_BELOW bor ?WALL_RIGHT);
	      true ->
		   Maze1 = set_maze_loc(6, 7, Maze0,
					?WALL_ABOVE bor ?WALL_BELOW),
		   set_maze_loc(8, 7, Maze1,
				?WALL_ABOVE bor ?WALL_BELOW)
	   end,
    G#game { maze = Maze,
	     scared = Scared,
	     scaredcount = ScaredCount,
	     mazecolor = MazeColor
	    }.


check_maze(G) ->
    Maze0 = G#game.maze,
    Max = ?NBlocks*?NBlocks,
    I1 = while(0,
	       fun(I) ->
		       (I < Max) andalso
		       ((get_maze_pos(I, Maze0) band
			 (?FOOD_SMALL bor ?FOOD_BIG)) == 0)
	       end,
	       fun(I) -> I + 1 end),
    case (I1 >= Max) of
	true ->
	    G1 = G#game { score = G#game.score + 50 },
	    G2 = draw_score(G1),
	    receive after 3000 -> ok end,
	    NrOfGhosts = if G2#game.nrofghosts < ?MaxGhosts ->
				 G2#game.nrofghosts + 1;
			    true ->
				 G2#game.nrofghosts
			 end,
	    CurrentSpeed = if G2#game.currentspeed < ?MaxSpeed ->
				   G2#game.currentspeed+1;
			      true ->
				   G2#game.currentspeed
			   end,
	    ScaredTime0 = G2#game.scaredtime - 20,
	    ScaredTime  = if ScaredTime0 < ?MinScaredTime ->
				  ?MinScaredTime;
			     true ->
				  ScaredTime0
			  end,
	    G3 = G2#game { nrofghosts = NrOfGhosts,
			   currentspeed = CurrentSpeed,
			   scaredtime   = ScaredTime },
	    level_init(G3);
	false ->
	    G
    end.


death(G) ->
    Image = G#game.images,
    DeathCounter = G#game.deathcounter - 1,
    K = (DeathCounter band 15) div 4,
    case K of
	0 -> draw_pacman(G, element(4,Image#images.pacman_up));
	1 -> draw_pacman(G, element(4,Image#images.pacman_right));
	2 -> draw_pacman(G, element(4,Image#images.pacman_down));
	_ -> draw_pacman(G, element(4,Image#images.pacman_left))
    end,
    if DeathCounter == 0 ->
	    PacsLeft = G#game.pacsleft - 1,
	    G1 = if PacsLeft == 0 ->
			 G#game { deathcounter = 0,
				  pacsleft = 0,
				  ingame = false };
		    true ->
			 G#game { deathcounter = 0, 
				  pacsleft = PacsLeft}
		 end,
	    level_continue(G1);
       true ->
	    G#game { deathcounter = DeathCounter }
    end.


show_intro_screen(G) ->
    draw_text(G, {30, G#game.width div 2}, "Press 's' to start qame", {250,250,0}),
    G.

move_pacman(G) ->
    move_pacman(G, G#game.pacman).

%% check if user want a direction change
move_pacman(G, P) ->
    Dx = G#game.reqdx,
    Dy = G#game.reqdy,
    if Dx == -P#pacman.dx,
       Dy == -P#pacman.dy ->
	    check_pacman(G#game { viewdx = Dx, viewdy = Dy },
			 P#pacman { dx=Dx, dy=Dy });
       true ->
	    check_pacman(G, P)
    end.

%% check if we are in a junction
check_pacman(G, P) ->
    if ?XToLoc(P#pacman.x) == 0, ?YToLoc(P#pacman.y) == 0 ->
	    junction_pacman(G, P);
       true ->
	    forward_pacman(G, P, 0, ?PacManSpeed)
    end.
%%
%% pacman in a possible junction
%%
junction_pacman(G, P) ->
    Maze = G#game.maze,
    Pos  = ?CoordToPos(P#pacman.x, P#pacman.y),
    Z = get_maze_pos(Pos, Maze),
    if ?IS_FOOD_SMALL(Z) ->
	    Z1 = Z band 16#0f,
	    Maze1 = set_maze_pos(Pos, Maze, Z1),
	    Score = G#game.score + 1,
	    turn_pacman(G#game { maze = Maze1, score = Score },
			 P, Z1);
       ?IS_FOOD_BIG(Z) ->
	    Z1 = Z band 16#0f,
	    Maze1 = set_maze_pos(Pos, Maze, Z1),
	    Score = G#game.score + 5,
	    turn_pacman(G#game { maze = Maze1, score = Score,
				 scared = true,
				 scaredcount = G#game.scaredtime },
			 P, Z1);
       true ->
	    turn_pacman(G, P, Z)
    end.


%%% Check if pacman wants to turn
turn_pacman(G,P,Z) ->
    Dx = G#game.reqdx,
    Dy = G#game.reqdy,
    if Dx== 0, Dy== 0 -> block_pacman(G,P,Z);
       Dx==-1, Dy== 0, ?IS_WALL_LEFT(Z)  -> block_pacman(G,P,Z);
       Dx== 1, Dy== 0, ?IS_WALL_RIGHT(Z) -> block_pacman(G,P,Z);
       Dx== 0, Dy==-1, ?IS_WALL_ABOVE(Z) -> block_pacman(G,P,Z);
       Dx== 0, Dy== 1, ?IS_WALL_BELOW(Z) -> block_pacman(G,P,Z);
       true ->
	    block_pacman(G#game { viewdx=Dx, viewdy=Dy },
			 P#pacman { dx = Dx, dy = Dy }, Z)
    end.

%% stop pacman from going into wall.
block_pacman(G,P,Z)->
    Dx = P#pacman.dx,
    Dy = P#pacman.dy,
    if Dx==-1, Dy==0, ?IS_WALL_LEFT(Z) ->
	    forward_pacman(G, P, Z, 0);
       Dx==1, Dy==0, ?IS_WALL_RIGHT(Z) ->
	    forward_pacman(G, P, Z, 0);
       Dx==0, Dy==-1, ?IS_WALL_ABOVE(Z) ->
	    forward_pacman(G, P, Z, 0);
       Dx==0, Dy==1, ?IS_WALL_BELOW(Z) ->
	    forward_pacman(G, P, Z, 0);
       true ->
	    forward_pacman(G, P, Z, ?PacManSpeed)
    end.

%% move pacman accoring to direction and speed
forward_pacman(G,P,_Z,Speed) ->
    X = P#pacman.x + Speed*P#pacman.dx,
    Y = P#pacman.y + Speed*P#pacman.dy,
    G#game { pacman = P#pacman { x = X, y = Y }}.

draw_pacman(G) ->
    Image = G#game.images,
    Pos = G#game.pacmananimpos + 1,
    if G#game.viewdx == 1 ->
	    draw_pacman(G, element(Pos, Image#images.pacman_right));
       G#game.viewdy == -1 ->
	    draw_pacman(G, element(Pos, Image#images.pacman_up));
       G#game.viewdy == 1 ->
	    draw_pacman(G, element(Pos, Image#images.pacman_down));
       true ->
	    draw_pacman(G, element(Pos, Image#images.pacman_left))
    end.

draw_pacman(G, Image) ->
    PacMan = G#game.pacman,
    draw_image(Image, PacMan#pacman.x+1, PacMan#pacman.y+1).

draw_ghost(G, H) ->
    X = H#ghost.x,
    Y = H#ghost.y,
    Image = G#game.images,
    if G#game.ghostanimpos == 0, G#game.scared == false ->
	    draw_image(Image#images.ghost1, X+1, Y+1);
       G#game.ghostanimpos == 1, G#game.scared == false ->
	    draw_image(Image#images.ghost2, X+1, Y+1);
       G#game.ghostanimpos == 0, G#game.scared == true ->
	    draw_image(Image#images.ghostscared1, X+1, Y+1);
       G#game.ghostanimpos == 1, G#game.scared == true ->
	    draw_image(Image#images.ghostscared2, X+1, Y+1);
       true ->
	    ok
    end.

draw_image({Rotate, Pixmap}, X, Y) ->
    gl:enable(?GL_TEXTURE_2D),
    gl:bindTexture(?GL_TEXTURE_2D, Pixmap),
    gl:pushMatrix(),
    gl:translatef(X+11,Y+11,0.0),
    gl:rotatef(Rotate, 0.0,0.0,1.0),
    gl:'begin'(?GL_QUADS),
    MaxX = MaxY = 22/32,
    gl:texCoord2f(MaxX, MaxY), gl:vertex2i(-11,-11),
    gl:texCoord2f(0.0,  MaxY), gl:vertex2i( 11,-11),
    gl:texCoord2f(0.0,  0.0),  gl:vertex2i( 11, 11),
    gl:texCoord2f(MaxX, 0.0),  gl:vertex2i(-11, 11),
    gl:'end'(),
    gl:popMatrix(),
    gl:disable(?GL_TEXTURE_2D);
draw_image(TId, X, Y) ->
    gl:enable(?GL_TEXTURE_2D),
    gl:bindTexture(?GL_TEXTURE_2D, TId),
    gl:'begin'(?GL_QUADS),
    MaxX = MaxY = 22/32,
    gl:texCoord2f(MaxX, MaxY), gl:vertex2i(X,   Y),
    gl:texCoord2f(0.0,  MaxY), gl:vertex2i(X+22,Y),
    gl:texCoord2f(0.0,  0.0),  gl:vertex2i(X+22,Y+22),
    gl:texCoord2f(MaxX, 0.0),  gl:vertex2i(X,   Y+22),
    gl:'end'(),
    gl:disable(?GL_TEXTURE_2D).


move_ghosts(G) ->
    move_ghosts(G, G#game.ghosts, []).

move_ghosts(G, [H|Hs], Acc) ->
    {G1,H1} = move_ghost(G,H),
    move_ghosts(G1, Hs, [H1|Acc]);
move_ghosts(G, [], Acc) ->
    G#game { ghosts = lists:reverse(Acc) }.


move_ghost(G, H) ->
    Maze = G#game.maze,
    {Dx,Dy} =
	if ?XToLoc(H#ghost.x) == 0, ?YToLoc(H#ghost.y) == 0 ->
		Pos = ?CoordToPos(H#ghost.x,H#ghost.y),
		Z = get_maze_pos(Pos, Maze),
		LDxy =
		    if H#ghost.dx =/= 1, ?NO_WALL_LEFT(Z) ->
			    [{-1, 0}];
		       true ->
			    []
		    end ++
		    if H#ghost.dx =/= -1, ?NO_WALL_RIGHT(Z) ->
			    [{1, 0}];
		       true ->
			    []
		    end ++
		    if H#ghost.dy =/= 1, ?NO_WALL_ABOVE(Z) ->
			    [{0, -1}];
		       true ->
			    []
		    end ++
		    if  H#ghost.dy =/= -1, ?NO_WALL_BELOW(Z) ->
			    [{0, 1}];
		       true ->
			    []
		    end,
		Count = length(LDxy),
		if Count == 0 ->
			if Z band 16#0F == 16#0F -> {0,0};
			   true -> { -H#ghost.dx, -H#ghost.dy }
			end;
		   true ->
			case random:uniform(Count) of
			    1 -> [Dxy|_] = LDxy, Dxy;
			    2 -> [_,Dxy|_] = LDxy, Dxy;
			    3 -> [_,_,Dxy|_] = LDxy, Dxy;
			    4 -> [_,_,_,Dxy] = LDxy, Dxy
			end
		end;
	   true ->
		{ H#ghost.dx, H#ghost.dy }
	end,
    Speed = H#ghost.speed,
    X = H#ghost.x + Dx*Speed,
    Y = H#ghost.y + Dy*Speed,
    H1 = H#ghost { x = X, y = Y, dx = Dx, dy = Dy },
    draw_ghost(G, H1),
    P = G#game.pacman,
    if P#pacman.x > X-12, P#pacman.x < X+12,
       P#pacman.y > Y-12, P#pacman.y < Y+12,
       G#game.ingame == true ->
	    if G#game.scared == true ->
		    G1 = G#game { score = G#game.score + 10 },
		    H2 = H1#ghost { x = 7*?BlockSize,
				    y = 7*?BlockSize },
		    {G1,H2};
	       true ->
		    G1 = G#game { dying = true,
				  deathcounter = 64 },
		    {G1, H1}
	    end;
       true ->
	    {G, H1}
    end.

%%
%% Maze stuff
%%
level1data() ->
    {
	    19,26,26,22, 9,12,19,26,22, 9,12,19,26,26,22,
	    37,11,14,17,26,26,20,15,17,26,26,20,11,14,37,
	    17,26,26,20,11, 6,17,26,20, 3,14,17,26,26,20,
	    21, 3, 6,25,22, 5,21, 7,21, 5,19,28, 3, 6,21,
	    21, 9, 8,14,21,13,21, 5,21,13,21,11, 8,12,21,
	    25,18,26,18,24,18,28, 5,25,18,24,18,26,18,28,
	    6,21, 7,21, 7,21,11, 8,14,21, 7,21, 7,21,03,
	    4,21, 5,21, 5,21,11,10,14,21, 5,21, 5,21, 1,
	    12,21,13,21,13,21,11,10,14,21,13,21,13,21, 9,
	    19,24,26,24,26,16,26,18,26,16,26,24,26,24,22,
	    21, 3, 2, 2, 6,21,15,21,15,21, 3, 2, 2,06,21,
	    21, 9, 8, 8, 4,17,26, 8,26,20, 1, 8, 8,12,21,
	    17,26,26,22,13,21,11, 2,14,21,13,19,26,26,20,
	    37,11,14,17,26,24,22,13,19,24,26,20,11,14,37,
	    25,26,26,28, 3, 6,25,26,28, 3, 6,25,26,26,28
	   }.

%% get maze data with either straigh pos, location or coordinate
get_maze_pos(Pos, Maze) ->
    element(Pos+1, Maze).

%% get_maze_xy(X, Y, Maze) ->
%%     element(?CoordToPos(X, Y)+1, Maze).

%% get_maze_loc(I, J, Maze) ->
%%     element(?LocToPos(I, J)+1, Maze).

%% set maze data with either straigh pos, location or coordinate

set_maze_pos(Pos, Maze, Code) ->
    setelement(Pos+1, Maze, Code).

%% set_maze_xy(X, Y, Maze, Code) ->
%%     setelement(?CoordToPos(X,Y)+1, Maze, Code).

set_maze_loc(I, J, Maze, Code) ->
    setelement(?LocToPos(I,J)+1, Maze, Code).

%% change direction if Pos <= Min or Pos >= Max
bounce(Pos, Min, Max, Dir) ->
    if Pos =< Min -> -Dir;
       Pos >= Max -> -Dir;
       true -> Dir
    end.

%%
%% Utilities
%%

each(I, N, Fun) ->
    if I > N -> ok;
       true ->
	    Fun(I),
	    each(I+1, N, Fun)
    end.

%% each(I, Step, N, Fun) ->
%%     if I > N -> ok;
%%        true ->
%% 	    Fun(I),
%% 	    each(I+Step, Step, N, Fun)
%%     end.


while(Acc, Done, Body) ->
    case Done(Acc) of
	true ->
	    Acc1 = Body(Acc),
	    while(Acc1, Done, Body);
	false -> Acc
    end.
