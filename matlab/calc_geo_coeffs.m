%% calc_geo_coeffs.m
% 功能：
%   计算“缩放 + 顺时针旋转”的统一逆映射系数，并给出 FPGA 定点化结果
%
% 公式：
%   xs = a00 * xo + a01 * yo + bx
%   ys = a10 * xo + a11 * yo + by
%
% 坐标系约定：
%   x 向右，y 向下
%   theta > 0 表示顺时针旋转
%
% 作者注：
%   本脚本默认：
%   1) 缩放因子由输入/输出尺寸自动决定：Sx = Wo/Ws, Sy = Ho/Hs
%   2) 旋转中心和缩放中心都取图像中心
%   3) 中心采用像素中心模型：(W-1)/2, (H-1)/2

clear; clc;

%% =========================
% 1. 用户输入区
% ==========================
Ws = 7200;   % 源图宽
Hs = 6000;   % 源图高

Wo = 4000;   % 输出图宽
Ho = 2000;   % 输出图高

theta_deg = 40;   % 顺时针旋转角度（单位：度）

% FPGA 定点格式设置
Q_FRAC = 16;      % Q15.16 里的小数位数
Q_SCALE = 2^Q_FRAC;

%% =========================
% 2. 基本参数计算
% ==========================
Sx = Wo / Ws;
Sy = Ho / Hs;

csx = (Ws - 1) / 2;
csy = (Hs - 1) / 2;

cox = (Wo - 1) / 2;
coy = (Ho - 1) / 2;

theta_rad = deg2rad(theta_deg);
c = cos(theta_rad);
s = sin(theta_rad);

%% =========================
% 3. 统一逆映射系数
%    xs = a00*xo + a01*yo + bx
%    ys = a10*xo + a11*yo + by
% ==========================
a00 =  c / Sx;
a01 =  s / Sx;
a10 = -s / Sy;
a11 =  c / Sy;

bx = csx - (cox * c + coy * s) / Sx;
by = csy - (-cox * s + coy * c) / Sy;

%% =========================
% 4. 递推步进
% ==========================
dx_col = a00;   % xo 每 +1，xs 增量
dy_col = a10;   % xo 每 +1，ys 增量

dx_row = a01;   % yo 每 +1，xs 增量
dy_row = a11;   % yo 每 +1，ys 增量

%% =========================
% 5. 左上角起点（输出坐标 (0,0)）
% ==========================
xs_00 = bx;
ys_00 = by;

%% =========================
% 6. 几个角点对应的源图坐标（便于检查）
% ==========================
corners_out = [
    0,     0;
    Wo-1,  0;
    0,     Ho-1;
    Wo-1,  Ho-1
];

corners_src = zeros(size(corners_out));

for k = 1:size(corners_out, 1)
    xo = corners_out(k, 1);
    yo = corners_out(k, 2);

    xs = a00 * xo + a01 * yo + bx;
    ys = a10 * xo + a11 * yo + by;

    corners_src(k, :) = [xs, ys];
end

%% =========================
% 7. 定点量化（Q15.16）
% ==========================
toQ = @(x) round(x * Q_SCALE);

a00_q = toQ(a00);
a01_q = toQ(a01);
a10_q = toQ(a10);
a11_q = toQ(a11);
bx_q  = toQ(bx);
by_q  = toQ(by);

dx_col_q = toQ(dx_col);
dy_col_q = toQ(dy_col);
dx_row_q = toQ(dx_row);
dy_row_q = toQ(dy_row);

xs_00_q = toQ(xs_00);
ys_00_q = toQ(ys_00);

%% =========================
% 8. 估算坐标范围（便于检查位宽）
%    用四角粗略检查
% ==========================
xs_min = min(corners_src(:,1));
xs_max = max(corners_src(:,1));
ys_min = min(corners_src(:,2));
ys_max = max(corners_src(:,2));

%% =========================
% 9. 打印结果
% ==========================
fprintf('================ 基本参数 ================\n');
fprintf('源图尺寸: Ws = %d, Hs = %d\n', Ws, Hs);
fprintf('输出尺寸: Wo = %d, Ho = %d\n', Wo, Ho);
fprintf('旋转角度: theta = %.6f deg (顺时针为正)\n', theta_deg);
fprintf('\n');

fprintf('Sx = Wo / Ws = %.12f\n', Sx);
fprintf('Sy = Ho / Hs = %.12f\n', Sy);
fprintf('\n');

fprintf('源图中心:  csx = %.12f, csy = %.12f\n', csx, csy);
fprintf('输出中心:  cox = %.12f, coy = %.12f\n', cox, coy);
fprintf('\n');

fprintf('cos(theta) = %.12f\n', c);
fprintf('sin(theta) = %.12f\n', s);
fprintf('\n');

fprintf('============= 统一逆映射系数 =============\n');
fprintf('xs = a00 * xo + a01 * yo + bx\n');
fprintf('ys = a10 * xo + a11 * yo + by\n\n');

fprintf('a00 = %.12f\n', a00);
fprintf('a01 = %.12f\n', a01);
fprintf('a10 = %.12f\n', a10);
fprintf('a11 = %.12f\n', a11);
fprintf('bx  = %.12f\n', bx);
fprintf('by  = %.12f\n', by);
fprintf('\n');

fprintf('============= 递推步进（浮点） ============\n');
fprintf('列方向步进: dx_col = %.12f, dy_col = %.12f\n', dx_col, dy_col);
fprintf('行方向步进: dx_row = %.12f, dy_row = %.12f\n', dx_row, dy_row);
fprintf('左上角起点: xs_00  = %.12f, ys_00  = %.12f\n', xs_00, ys_00);
fprintf('\n');

fprintf('============= 角点映射检查 ================\n');
for k = 1:size(corners_out, 1)
    fprintf('out(%6d, %6d) -> src(%12.6f, %12.6f)\n', ...
        corners_out(k,1), corners_out(k,2), ...
        corners_src(k,1), corners_src(k,2));
end
fprintf('\n');

fprintf('源坐标覆盖范围（由四角粗略估计）:\n');
fprintf('xs in [%.6f, %.6f]\n', xs_min, xs_max);
fprintf('ys in [%.6f, %.6f]\n', ys_min, ys_max);
fprintf('\n');

fprintf('============= Q15.16 定点结果 =============\n');
fprintf('Q_FRAC  = %d\n', Q_FRAC);
fprintf('Q_SCALE = %d\n\n', Q_SCALE);

fprintf('a00_q = %d\n', a00_q);
fprintf('a01_q = %d\n', a01_q);
fprintf('a10_q = %d\n', a10_q);
fprintf('a11_q = %d\n', a11_q);
fprintf('bx_q  = %d\n', bx_q);
fprintf('by_q  = %d\n', by_q);
fprintf('\n');

fprintf('dx_col_q = %d\n', dx_col_q);
fprintf('dy_col_q = %d\n', dy_col_q);
fprintf('dx_row_q = %d\n', dx_row_q);
fprintf('dy_row_q = %d\n', dy_row_q);
fprintf('xs_00_q  = %d\n', xs_00_q);
fprintf('ys_00_q  = %d\n', ys_00_q);
fprintf('\n');

%% =========================
% 10. 保存结果到结构体
% ==========================
param = struct();

param.Ws = Ws;
param.Hs = Hs;
param.Wo = Wo;
param.Ho = Ho;
param.theta_deg = theta_deg;
param.theta_rad = theta_rad;

param.Sx = Sx;
param.Sy = Sy;

param.csx = csx;
param.csy = csy;
param.cox = cox;
param.coy = coy;

param.cos_theta = c;
param.sin_theta = s;

param.a00 = a00;
param.a01 = a01;
param.a10 = a10;
param.a11 = a11;
param.bx  = bx;
param.by  = by;

param.dx_col = dx_col;
param.dy_col = dy_col;
param.dx_row = dx_row;
param.dy_row = dy_row;

param.xs_00 = xs_00;
param.ys_00 = ys_00;

param.corners_out = corners_out;
param.corners_src = corners_src;

param.Q_FRAC = Q_FRAC;
param.Q_SCALE = Q_SCALE;

param.a00_q = a00_q;
param.a01_q = a01_q;
param.a10_q = a10_q;
param.a11_q = a11_q;
param.bx_q  = bx_q;
param.by_q  = by_q;

param.dx_col_q = dx_col_q;
param.dy_col_q = dy_col_q;
param.dx_row_q = dx_row_q;
param.dy_row_q = dy_row_q;

param.xs_00_q = xs_00_q;
param.ys_00_q = ys_00_q;

save('geo_param.mat', 'param');

fprintf('结果已保存到 geo_param.mat\n');