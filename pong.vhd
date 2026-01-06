-- pong_vga.vhd – Pong em VGA 800×600 @ 72 Hz para DE10-Lite (MAX 10)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pong is
  port (
    MAX10_CLK1_50 : in  std_logic;
    VGA_R, VGA_G, VGA_B : out std_logic_vector(3 downto 0);
    VGA_HS, VGA_VS      : out std_logic;
	 -- BOTÕES DE COMANDO
	 ARDUINO_IO	:	in std_logic_vector(0 to 15)
		  -- ARDUINO_IO(2) p1_up
		  -- ARDUINO_IO(3) p1_dw
		  -- ARDUINO_IO(6) p2_up
		  -- ARDUINO_IO(7) p2_dw
  );
end entity;

architecture rtl of pong is
  ------------------------------------------------------------------
  -- 1. Temporização VGA 800×600 @ 72 Hz (clock 50 MHz) --------------
  ------------------------------------------------------------------
  constant H_VISIBLE     : integer := 800;
  constant H_FRONT_PORCH : integer := H_VISIBLE + 56;
  constant H_SYNC_END    : integer := H_FRONT_PORCH + 120;
  constant H_BACK_PORCH  : integer := H_SYNC_END + 64;
  constant H_TOTAL       : integer := 1040;

  constant V_VISIBLE     : integer := 600;
  constant V_FRONT_PORCH : integer := V_VISIBLE + 37;
  constant V_SYNC_END    : integer := V_FRONT_PORCH + 6;
  constant V_BACK_PORCH  : integer := V_SYNC_END + 23;
  constant V_TOTAL       : integer := 666;

  ------------------------------------------------------------------
  -- 2. Parâmetros do jogo ------------------------------------------
  ------------------------------------------------------------------
  constant PADDLE_W      : integer := 16;
  constant PADDLE_H      : integer := 128;
  constant PADDLE_SPEED  : integer := 4;

  constant BALL_SZ       : integer := 16;
  constant BALL_DX_INIT  : integer := 4;
  constant BALL_DY_INIT  : integer := 4;

  constant P1_X          : integer := 30;
  constant P2_X          : integer := H_VISIBLE - 30 - PADDLE_W;

  -- Cores RGB 4-4-4
  constant C_BLACK  : std_logic_vector(11 downto 0) := x"000";
  constant C_PADDLE : std_logic_vector(11 downto 0) := x"0FF";
  constant C_BALL   : std_logic_vector(11 downto 0) := x"FFF";
  constant C_SCORE_L: std_logic_vector(11 downto 0) := x"0F0";
  constant C_SCORE_R: std_logic_vector(11 downto 0) := x"F00";

  ------------------------------------------------------------------
  -- 3. Sinais VGA ---------------------------------------------------
  ------------------------------------------------------------------
  signal h_cnt, v_cnt : integer range 0 to H_TOTAL-1 := 0;
  signal active_xy    : std_logic := '0';
  signal frame_tick   : std_logic := '0';
  signal hs_reg, vs_reg : std_logic := '1';

  ------------------------------------------------------------------
  -- 4. Estado do jogo ----------------------------------------------
  ------------------------------------------------------------------
  signal p1_y, p2_y : integer range 0 to V_VISIBLE := V_VISIBLE/2;

  signal ball_x : integer range -BALL_SZ to H_VISIBLE+BALL_SZ := H_VISIBLE/2;
  signal ball_y : integer range -BALL_SZ to V_VISIBLE+BALL_SZ := V_VISIBLE/2;
  signal ball_dx : integer := BALL_DX_INIT;
  signal ball_dy : integer := BALL_DY_INIT;

  signal score_l, score_r : integer range 0 to 9 := 0;

  ------------------------------------------------------------------
  -- 5. Desenho de retângulos ---------------------------------------
  ------------------------------------------------------------------
  procedure draw_rect (
    constant ena      : in  std_logic;
    constant px, py   : in  integer;
    constant cx, cy   : in  integer;
    constant w, h     : in  integer;
    constant color_in : in  std_logic_vector(11 downto 0);
    variable  pixcol  : inout std_logic_vector(11 downto 0)
  ) is
  begin
    if ena = '1' then
      if (px >= cx - w/2) and (px < cx + w/2) and
         (py >= cy - h/2) and (py < cy + h/2) then
        pixcol := color_in;
      end if;
    end if;
  end procedure;
begin
  ------------------------------------------------------------------
  -- 6. Gerador de HS/VS e contadores -------------------------------
  ------------------------------------------------------------------
  process (MAX10_CLK1_50)
    variable h_over, v_over : boolean;
  begin
    if rising_edge(MAX10_CLK1_50) then
      -- HS
      if (h_cnt >= H_FRONT_PORCH) and (h_cnt < H_SYNC_END) then
        hs_reg <= '0';
      else
        hs_reg <= '1';
      end if;
      -- VS
      if (v_cnt >= V_FRONT_PORCH) and (v_cnt < V_SYNC_END) then
        vs_reg <= '0';
      else
        vs_reg <= '1';
      end if;

      -- Região visível  (<<< trocado para IF)
      if (h_cnt < H_VISIBLE) and (v_cnt < V_VISIBLE) then
        active_xy <= '1';
      else
        active_xy <= '0';
      end if;

      -- Contador horizontal
      h_over := (h_cnt = H_TOTAL-1);
      if h_over then
        h_cnt <= 0;
      else
        h_cnt <= h_cnt + 1;
      end if;

      -- Contador vertical
      v_over := false;
      if h_over then
        v_over := (v_cnt = V_TOTAL-1);
        if v_over then
          v_cnt <= 0;
        else
          v_cnt <= v_cnt + 1;
        end if;
      end if;

      -- Pulso de frame  (<<< trocado para IF)
      if v_over then
        frame_tick <= '1';
      else
        frame_tick <= '0';
      end if;
    end if;
  end process;

  VGA_HS <= hs_reg;
  VGA_VS <= vs_reg;

  ------------------------------------------------------------------
  -- 7. Lógica do jogo (1× por frame) -------------------------------
  ------------------------------------------------------------------
  process (MAX10_CLK1_50)
    variable nxt_x, nxt_y : integer;
    variable nxt_dx, nxt_dy : integer;
  begin
    if rising_edge(MAX10_CLK1_50) then
      if frame_tick = '1' then
		  
		  -- CONTROLES
		  -- Controle do jogador 1
        if ARDUINO_IO(2) = '0' then
            if p1_y > 70 then
                p1_y <= p1_y - 5;
            end if;
        elsif ARDUINO_IO(3) = '0' then
            if p1_y < V_VISIBLE - 60 then
                p1_y <= p1_y + 5;
            end if;
        end if;

        -- Controle do jogador 2
        if ARDUINO_IO(6) = '0' then
            if p2_y > 70 then
                p2_y <= p2_y - 5;
            end if;
        elsif ARDUINO_IO(7) = '0' then
            if p2_y < V_VISIBLE - 60 then
                p2_y <= p2_y + 5;
            end if;
        end if;
		  -- CONTROLES. JM

        -- Próxima posição da bola
        nxt_x  := ball_x + ball_dx;
        nxt_y  := ball_y + ball_dy;
        nxt_dx := ball_dx;
        nxt_dy := ball_dy;

        -- Bordas superior/inferior
        if nxt_y <= BALL_SZ/2 then
          nxt_y  := BALL_SZ/2;
          nxt_dy :=  BALL_DY_INIT;
        elsif nxt_y >= V_VISIBLE - BALL_SZ/2 then
          nxt_y  := V_VISIBLE - BALL_SZ/2;
          nxt_dy := -BALL_DY_INIT;
        end if;

        -- Paddle esquerdo
        if (nxt_dx < 0) and
           (nxt_x - BALL_SZ/2 <= P1_X + PADDLE_W/2) and
           (nxt_y >= p1_y-PADDLE_H/2) and (nxt_y <= p1_y+PADDLE_H/2) then
          nxt_x  := P1_X + PADDLE_W/2 + BALL_SZ/2;
          nxt_dx :=  BALL_DX_INIT;
          nxt_dy := -nxt_dy;
        end if;

        -- Paddle direito
        if (nxt_dx > 0) and
           (nxt_x + BALL_SZ/2 >= P2_X - PADDLE_W/2) and
           (nxt_y >= p2_y-PADDLE_H/2) and (nxt_y <= p2_y+PADDLE_H/2) then
          nxt_x  := P2_X - PADDLE_W/2 - BALL_SZ/2;
          nxt_dx := -BALL_DX_INIT;
          nxt_dy := -nxt_dy;
        end if;

        -- Atualiza posição/velocidade
        ball_x  <= nxt_x;
        ball_y  <= nxt_y;
        ball_dx <= nxt_dx;
        ball_dy <= nxt_dy;

        -- Pontuação / reset
        if nxt_x < -BALL_SZ then                -- ponto P2
          score_r <= (score_r + 1) mod 10;
          ball_x  <= H_VISIBLE/2;
          ball_y  <= V_VISIBLE/2;
          ball_dx <=  BALL_DX_INIT;
          ball_dy <=  BALL_DY_INIT;
        elsif nxt_x > H_VISIBLE + BALL_SZ then  -- ponto P1
          score_l <= (score_l + 1) mod 10;
          ball_x  <= H_VISIBLE/2;
          ball_y  <= V_VISIBLE/2;
          ball_dx <= -BALL_DX_INIT;
          ball_dy <=  BALL_DY_INIT;
        end if;
      end if; -- frame_tick
    end if;   -- clk
  end process;

  ------------------------------------------------------------------
  -- 8. Gerador de pixels ------------------------------------------
  ------------------------------------------------------------------
  process (h_cnt, v_cnt, active_xy,
           p1_y, p2_y, ball_x, ball_y, score_l, score_r)
    variable pix : std_logic_vector(11 downto 0);
  begin
    pix := C_BLACK;

    -- Paddles
    draw_rect(active_xy, h_cnt, v_cnt,
              P1_X + PADDLE_W/2, p1_y, PADDLE_W, PADDLE_H,
              C_PADDLE, pix);
    draw_rect(active_xy, h_cnt, v_cnt,
              P2_X + PADDLE_W/2, p2_y, PADDLE_W, PADDLE_H,
              C_PADDLE, pix);

    -- Bola
    draw_rect(active_xy, h_cnt, v_cnt,
              ball_x, ball_y, BALL_SZ, BALL_SZ,
              C_BALL, pix);

    -- Placar (até 9 quadrados)
    for i in 0 to 8 loop
      if i < score_l then
        draw_rect(active_xy, h_cnt, v_cnt,
                  20 + i*20, 20, 14, 14, C_SCORE_L, pix);
      end if;
      if i < score_r then
        draw_rect(active_xy, h_cnt, v_cnt,
                  H_VISIBLE-20 - i*20, 20, 14, 14, C_SCORE_R, pix);
      end if;
    end loop;

    VGA_R <= pix(11 downto 8);
    VGA_G <= pix(7 downto 4);
    VGA_B <= pix(3 downto 0);
  end process;
end architecture;