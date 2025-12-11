% Wavelet coherence: Bz (OMNI) x Vd_{mean,storm,total}
clc; clear; close all;

% --- 1) Carregar dados ionosféricos (para criar eixo temporal 5 min)
load('mediasionosfericasARG.mat');  % contém foF2, hF, hmF2
N = length(foF2);
start_time = datetime('01-Aug-2017 00:00', 'InputFormat', 'dd-MMM-yyyy HH:mm');
iono_time = start_time + minutes(5*(0:(N-1)));   % 5-min grid

% --- 2) Ler arquivo OMNI
fid = fopen('dados_Omni_Tratados.txt');
data = textscan(fid, '%d %d %d %s %f %f %f %f %f %f', ...
    'Delimiter', '\t', 'CollectOutput', false);
fclose(fid);

dia = data{1};
mes = data{2};
ano = data{3};
hora_str = data{4};

% quebrar 'HH:MM'
hora_min = split(hora_str, ':');
HR = str2double(hora_min(:,1));
MN = str2double(hora_min(:,2));

% criar datetime do OMNI
omni_time = datetime(ano, mes, dia, HR, MN, zeros(length(dia),1));

% Extrair colunas: conforme definição original
omni_data = [data{5}, data{6}, data{7}, data{8}, data{9}, data{10}];
omni_names = {'Bz (nT)', 'Vsw (km/s)', 'Density (n/cc)', ...
              'Ey (mV/m)', 'AE (nT)', 'SYM/H (nT)'};

% --- Agora usamos Bz (1ª coluna do omni_data)
Bz_raw = omni_data(:,1);

% --- 3) Ler arquivo drift.dat (Vd's)
disp('Lendo drift.dat ...');
d = importdata('drift.dat');
Vd_mean  = d(:,3);
Vd_storm = d(:,4);
Vd_total = d(:,5);
PPEF  = d(:,6);
DDEF  = d(:,7);

% criar tempo do drift (15 min)
nV = length(Vd_mean);
startV = datetime(2017,8,1,0,0,0);
Vd_time = startV + minutes(15*(0:(nV-1)));

% --- 4) Interpolar Bz e Vd's para o grid ionosférico (5 min)
x_omni = datenum(omni_time);
xq = datenum(iono_time);

Bz_interp = interp1(x_omni, Bz_raw, xq, 'linear', NaN);

% Interpolar Vd's
x_vd = datenum(Vd_time);
Vd_mean_interp  = interp1(x_vd, Vd_mean,  xq, 'linear', NaN);
Vd_storm_interp = interp1(x_vd, Vd_storm, xq, 'linear', NaN);
Vd_total_interp = interp1(x_vd, Vd_total, xq, 'linear', NaN);
PPEF_interp = interp1(x_vd, PPEF, xq, 'linear', NaN);
DDEF_interp = interp1(x_vd, DDEF, xq, 'linear', NaN);

% Agrupar sinais
signals = {
    Vd_mean_interp, 'Vd_{mean}';
    Vd_storm_interp, 'Vd_{storm}';
    Vd_total_interp, 'Vd_{total}';
    PPEF_interp,     'PPEF';
    DDEF_interp,     'DDEF';
};

% --- 5) Parâmetros para wcoherence
fs = 1/300;   % 5 min = 300 s

for k = 1:size(signals, 1)
    sig_vd = signals{k,1};
    nome_vd = signals{k,2};
    
    sig1 = Bz_interp(:);  % Bz
    sig2 = sig_vd(:);     % Vd ou PPEF ou DDEF
    
    fprintf('>> %s: Bz válidos = %d / %d ; %s válidos = %d / %d\n', ...
        'Bz vs Signal', sum(isfinite(sig1)), length(sig1), ...
        nome_vd, sum(isfinite(sig2)), length(sig2));
    
    mask_nan = isnan(sig1) | isnan(sig2);
    sig1_clean = sig1; sig2_clean = sig2;
    sig1_clean(isnan(sig1_clean)) = 0;
    sig2_clean(isnan(sig2_clean)) = 0;
    
    % extensão simétrica
    left1 = flipud(sig1_clean);
    sig1_ext = [left1; left1; sig1_clean; left1; left1];
    left2 = flipud(sig2_clean);
    sig2_ext = [left2; left2; sig2_clean; left2; left2];
    
    fb = cwtfilterbank('SignalLength', numel(sig2_ext), ...
                       'SamplingFrequency', fs, ...
                       'FrequencyLimits', [1e-7 1e-4]);
    
    dt = 300; % segundos
    [WCOH, ~, period, coi] = wcoherence(sig1_ext, sig2_ext, seconds(dt), 'FilterBank', fb);

    % Cortar parte central (dados originais)
    n = length(sig1_clean);
    try
        wcoh_central = WCOH(62:147, 2*n+1:3*n);
        coi_central  = coi(2*n+1:3*n);
        period_sel   = period(62:147,1);
    catch
        wcoh_central = WCOH(:, 2*n+1:3*n);
        coi_central  = coi(2*n+1:3*n);
        period_sel   = period(:,1);
    end

    % Máscara de NaNs
    wcoh_central(:, mask_nan) = NaN;

    % Converter período
    period_days = days(period_sel);
    period_log = log2(period_days);
    period_log_inv = flipud(period_log);
    wcoh_central = flipud(wcoh_central);

    % --- Plot ---
    figure('Name', ['WCOH: Bz × ' nome_vd], 'NumberTitle','off');
    h = pcolor(datenum(iono_time), period_log_inv, wcoh_central);
    set(h, 'EdgeColor', 'none', 'AlphaData', ~isnan(wcoh_central));
colormap jet;
c = colorbar;                  % salva o handle corretamente
c.Limits = [0 1];
c.Ticks = 0.1:0.1:0.9;
c.TickLabels = string(c.Ticks);

    set(gca, 'Color', 'w');
    ax = gca;
    ax.YDir = 'normal';

    xticks_custom = datenum(datetime(2017,8,1):days(2):datetime(2017,8,31));
    ax.XTick = xticks_custom;
    ax.XTickLabel = datestr(xticks_custom, 'dd');
    ax.XTickLabelRotation = 90;

    % Escala de período
    periods2 = [0.25 0.5 1 2 4 8 16 31];
    yticks_log2 = log2(periods2);
    ax.YTick = yticks_log2;
    ax.YTickLabel = string(periods2);

    xlabel('Time (days)', 'FontSize', 16, 'FontWeight', 'bold');
    ylabel('Period (days)', 'FontSize', 16, 'FontWeight', 'bold');
    title(['Bz × ' nome_vd], ...
        'FontSize', 16, 'FontWeight', 'bold');

    ax.FontSize = 16;
    c.Label.FontSize = 16; c.FontSize = 16;
    
    xlim([datenum(datetime(2017,8,1)), datenum(datetime(2017,9,1))]);
    
    disp(['Plot criado: Bz × ' nome_vd]);
    
% --- Salvar figura automaticamente (simples)
folder = 'images';
if ~exist(folder, 'dir')
    mkdir(folder);
end

% criar nome de arquivo seguro (substituir {, }, espaço e / por _)
nome_file = ['WCOH_Fejer_Bz_' nome_vd];
nome_file = strrep(nome_file, '{','_');
nome_file = strrep(nome_file, '}','_');
nome_file = strrep(nome_file, ' ','_');
nome_file = strrep(nome_file, '/','_');
nome_file = strrep(nome_file, '\','_');

filename = fullfile(folder, [nome_file '.png']);

try
    saveas(gcf, filename);
    disp(['Figura salva em: ' filename]);
catch ME
    warning('Não foi possível salvar a figura: %s', ME.message);
end

end

disp('Terminado.');
