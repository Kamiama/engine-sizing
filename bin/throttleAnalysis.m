%% Engine Throttle Analysis
% Author: Kamon Blong (kblong@purdue.edu)
% First Created: 3/28/2023
% Last Updated: 3/28/2023

%function [] = throttleAnalysis(min_throttle_pct, F_max, A_t, eff_c_star, eff_c_f, P_c_max, P_e, fuel, fuel_weight, fuel_temp, oxidizer, oxidizer_temp, OF, CEA_input_name)

%{ 
Description: Takes throttle percent as an input and performs analysis to
    deduce engine performance over a given throttle range following the
    procedure outlined in chapter 4 of http://ltu.diva-portal.org/smash/get/diva2:1732226/FULLTEXT01.pdf

Assumptions:
    - Constant OF ratio across throttle range (possible improvement for
    the future)
    - Unchanging atmospheric conditions

Inputs:
    min_throttle_pct - minimum throttle percent as a decimal between 0 and 1
    F_max - maximum thrust [lbf]
    r_t - throat radius [in]
    P_c_max - maximum chamber pressure [psi]
    P_e - exit pressure [psi]
    fuel - fuel string for CEA [N/A]
    fuel_temp - fuel temperature [K]
    fuel_weight - fuel weights for fuel mixtures [N/A]
    oxidizer - oxidizer string for CEA [N/A]
    oxidizer_temp - oxidizer temperature [K]
    OF - oxidizer to fuel ratio [N/A]

Outputs: 
    F - thrust [lbf]
    P_c - chamber pressure [psi]
    m_dot - mass flow rate [lb/s]
%}

clear;
clc;

%% Identify OS & Generate Paths 

%% Initializion & Variable Definition

min_throttle_pct = .2;
F_max = 500;
A_t = 1.45;
P_c_max = 250;
P_e = 14.7;
P_a = P_e;
fuel = 'C3H8O,2propanol';
fuel_weight = 0;
fuel_temp = 293.15;
oxidizer = 'O2(L)';
oxidizer_temp = 90.17;
OF = 1.3;
CEA_input_name = 'test';
eff_c_f = .9;
eff_c_star = .94;
g = 32.174; % gravitational acceleration [ft/s^2]

fineness = 20;

% initialize throttle range and desired variable matrices
throttle = linspace(1, min_throttle_pct, fineness); % throttle percent matrix
Fs = F_max .* throttle; % thrust matrix with correct linear correlation
Fs_temp = zeros(1, fineness); % temporary thrust matrix for iterative solving
P_cs = P_c_max .* throttle; % initial chamber pressure matrix with initial assumption of linear correlation
P_es = zeros(1, fineness);
m_dots = zeros(1, fineness);
isps = zeros(1, fineness);


%% Get Parameters at Full Throttle

% run CEA at full throttle conditions (F_max, P_c_max)
[cea_c_star, ~, ~, ~, gamma, ~, ~, ~, ~, ~, ~, ~, ~, ~] = RunCEA(P_c_max, P_a, fuel, fuel_weight, fuel_temp, oxidizer, oxidizer_temp, OF, 0, 0, CEA_input_name, 0, 1);

% extract CEA values
c_star_max = cea_c_star * eff_c_star;
gamma_max = gamma(1); % chamber gamma

% solve for expansion ratio (Sutton EQ 3.25)
exp_ratio = 1/(((gamma_max+1)/2)^(1/(gamma_max-1)) * (P_e/P_c_max)^(1/gamma_max) * ((gamma_max+1)/(gamma_max-1)*(1-(P_e/P_c_max)^((gamma_max-1)/gamma_max)))^.5);

% solve for thrust coefficient (Sutton EQ 3.30)
c_f_max = (sqrt(((2*gamma_max^2)/(gamma_max-1)) * (2/(gamma_max+1))^((gamma_max+1)/(gamma_max-1)) * (1-(P_e/P_c_max)^((gamma_max-1)/gamma_max))) + (P_e-P_a)*exp_ratio/P_c_max) * eff_c_f;

% basic calculations
A_t = F_max / c_f_max / P_c_max;
m_dot = A_t / c_star_max * P_c_max * g; % mass flow rate at full throttle [lb/s]


%% Initial Solution for Throttle Range

% initialize loop variables
index = 1;
%F = F_max;
tolerance = .1;
max_iter = 1000;

% iteratively loop through entire P_c matrix
for P_c = P_cs
    % initialize loop variables
    iter = 0;
    P_c_guess = P_c;
    P_c_mx = P_c_max + 50;
    P_c_mn = P_c;

    % loop
    while abs(Fs(index) - Fs_temp(index)) > tolerance && iter < max_iter
        % run CEA for given P_c_new
        [cea_c_star, cea_isp, ~, ~, gamma, ~, ~, ~, ~, ~, ~, ~, ~, ~] = RunCEA(P_c_guess, P_a, fuel, fuel_weight, fuel_temp, oxidizer, oxidizer_temp, OF, 0, 0, CEA_input_name, 0, 1);
        
        % extract CEA values
        gamma = gamma(1);
        
        % solve for P_e numerically (Sutton EQ 3.25)
        func = @(P_e) 1/(((gamma+1)/2)^(1/(gamma-1)) * (P_e/P_c_guess)^(1/gamma) * ((gamma+1)/(gamma-1)*(1-(P_e/P_c_guess)^((gamma-1)/gamma)))^.5) - exp_ratio;
        x0 = P_a * 2 / 3; % initial guess for P_e
        options = optimset('Display', 'iter'); % display solver progress
        P_e = fsolve(func, x0, options); % use the numerical solver fsolve to find the solution for P_e
    
        % solve for thrust coefficient (Sutton EQ 3.30)
        c_f = (sqrt(((2*gamma^2)/(gamma-1)) * (2/(gamma+1))^((gamma+1)/(gamma-1)) * (1-(P_e/P_c_guess)^((gamma-1)/gamma))) + (P_e-P_a)*exp_ratio/P_c_guess) * eff_c_f;
  
        % calculate thrust
        Fs_temp(index) = A_t * c_f * P_c_guess;

        % update loop
        if Fs(index) > Fs_temp(index)
            P_c_mn = P_c_guess;
        else
            P_c_mx = P_c_guess;
        end
        P_c_guess = (P_c_mx + P_c_mn) / 2;
        iter = iter + 1;
    end

    % record variables to matrices
    Fs(index) = Fs_temp(index);
    m_dots(index) = A_t / (cea_c_star * eff_c_star) * P_c_guess * g;
    isps(index) = cea_isp * eff_c_star * eff_c_f;
    P_cs(index) = P_c_guess;
    P_es(index) = P_e;

    % increase matrix index
    index = index + 1;
end

%% Plot Results
figure(1)
hold on

subplot(1,3,1)
plot(Fs, P_cs, 'blue');
title('Chamber Pressure vs Throttle')
xlabel('Thrust [lbf]')
ylabel('Chamber Pressure [psi]')
axis([Fs(end) Fs(1) P_cs(end) P_cs(1)])
grid on

subplot(1,3,2)
plot(Fs, m_dots, 'blue');
title('Mass Flow Rate vs Throttle')
xlabel('Thrust [lbf]')
ylabel('Mass Flow Rate [lb/s]')
axis([Fs(end) Fs(1) m_dots(end) m_dots(1)])
grid on

subplot(1,3,3)
plot(Fs, isps, 'blue');
title('Isp vs Throttle')
xlabel('Thrust [lbf]')
ylabel('isp [sec]')
axis([Fs(end) Fs(1) isps(end) isps(1)])
grid on

sgtitle("Throttle Analysis:   " + F_max + "lbf, " + P_c_max + " psi P_c," + OF + " OF ratio, down to " + min_throttle_pct * 100 + "% throttle")

