%% HELP Regenerative Cooling Sizing Code
% Authors: Kamon Blong (kamon.blong@gmail.com), Jan Ayala, Andrew Radulovich
% First Created: 10/23/2022
% Last Updated: 11/14/2022

% function [] = sizeRegen(x_contour, r_contour, R_t, nozzle_regen_pct, mdotf, P_c, P_e, Oxidizer, Fuel, OF_ratio, wall_material)
   %{ 
    Description:
    This program sets fluid and material inputs and then iterates starting from a
    variable distance downstream of the throat and carries it through up to the injector face. 
    Channels have a constant width but have the option to change channel height to 
    decrease hydraulic diameter and increase fluid velocity (thereby increasing cooling
    effectiveness) in key locations. This method allows for optimal machining via CSJ
    with a slitter-saw CNC attatchment or via powder bed 3D printing.

    Program Methodology
    - take inputs from main sizing code
    - calculate optimal number of channels
    - prescribe channel inputs (pressure, temperature, mdot, ect)
    - run CEA and get bartz film coefficient axially along chamber
    - calculate minimum wall thickness at throat
    - begin iterating along channel length from nozzle end to the injector face
        - for each point, iterate through aspect ratio to find the maximum
        channel size possible without melting (below a certain prescribed size)
        - integrate heat entry and pressure loss for the given step size
        - repeat process all the way up the channel, checking for structural
        stability at each point - if there is a point where the channels overheat
        or the working fluid boils, lower the aspect ratio cap and repeat
    - run program again with new pressure drop value until the calculated exit 
    pressure equals the guessed exit pressure
    - once iterative sizing is complete, display axial wall thickness and
    channel depth on main engine contour plot
    
    Inputs:
    - x_contour: 
    - y_contour:
    - R_t: Throat Radius
    - nozzle_regen_pct: 
    - mdotf: Mass flow rate of fuel/coolant (lb/s)
    - P_c: Chamber Pressure
    - P_e: Exit Pressure
    - Oxidizer: 
    - Fuel:
    - OF_ratio: 
    - wall_material:
    
    Outputs: 
    - 
    
    Assumptions:
    - Steady state
    - No backside wall heat transfer
    - Equally distributed temperature inside channels
    - Wicking heat into fuel doesn't change bulk gas temperature

%}
%% Inputs
clear
clc

u = convertUnits;
A_t = 1.45; % in^2
P_c_max = 250;
P_e = 14.7;
fuel = 'C3H8O,2propanol';
fuel_weight = 0;
oxidizer = 'O2(L)';
oxidizer_temp = 90.17;
OF = 1.3;
CEA_input_name = 'test';
g = 32.174 * u.F2IN; % gravitational acceleration [in/s^2]


%% Parse variables

    % geometric properties
        D_c = 10; % 
        A_local = []; %Local Cross Sectional Areas of Engine
        dlocal = [];  %Local Cross Sections of Channels
        characteristic_length = 10; %Longest length of Channels 
        chamber_length = 7; %in
        R_t = sqrt(A_t / pi); % [in]
        D_t = R_t * 2; % diameter at nozzle throat [in]
        R_of_curve = 1.5 * D_t / 2; % [in]
        A_local = pi * (R_t) ^ 2; % local cross sectional areas of engine

    % channel geometry
        t_w = 0.002 * u.M2IN; % in
        height = 0.002 * u.M2IN;
        width = 0.002 * u.M2IN;
        length = 0.01 * u.M2IN;
        hydraulic_D = 4 * height * width / (2 * (height + width));
        area = width * length; % in^2
    
    % working fluid properties
        fuel_pressure = 250; % Psi
        fuel_temp = 293.15; % K

    % engine properties
        mdotf = 1.0555; %Coolant/fuel mass flow lb/s

    % wall material properties
        kw = 385 * 0.27733887194; % Thermal Conductivity of Wall [BTU/s-in-F]
        E = 10; %Youngs modulus of elaticisty of the tube wall material
        a = 10; %Thermal expansion coefficient of the tube wall material
        v = 24; %Poisson ration of the tube wall material

%% Calculate minimum wall thickness
% determine optimal wall thickness based on throat conditions (because this is the most extreme location in the engine)

% Set Initial Properties
numchannels = pi * (D_t + 0.8 * (D_t + 2 * t_w)) / (D_t + 2 * t_w); %Number of Channels (EQ 6.30) (Change the coefficient later)
mdotchan = mdotf / numchannels; %Mass flow of channel (EQ 6.31)

[c_star, ~, ~, M, gamma, P, T_c, rho, mu, Pr_gas, Mw, ~, son, cp] = RunCEA(P_c_max, P_e, fuel, fuel_weight, fuel_temp, oxidizer, oxidizer_temp, OF, 0, 0, CEA_input_name, 1, 1);
cp = cp / 4184; % BTU/lb-F
c_star = c_star * 12; % in/s
T_c = T_c - 459.67; % F

stepnum = 2;
qdotL = zeros(1, stepnum);
qdotG = zeros(1, stepnum);
T_wl = zeros(1, stepnum);
pressure = zeros(1, stepnum);

T_wg_i = 5000; % Initial Guess of Gas side Temperature [F]
max_T_wg = 120; % maximum hot wall temperature [K]
qdotTolerance = 0.0001;

% Set Inlet Properties i = 1
T_wg(1:stepnum) = T_wg_i;
fuel_temp(1:stepnum) = fuel_temp * u.K2R - 459.67; % F
fuel_pressure(1:stepnum) = fuel_pressure;

loc = 2;
iter = 0; % Number of convergence loops
step = 1000;
i = 2;
while i <= stepnum
    % Gas Side
    sigma = (.5 * T_wg(i) / T_c(loc) * (1 + (gamma(loc) - 1) / 2 * M(loc) ^ 2) + .5) ^ -.68 * (1 + (gamma(loc) - 1) / 2 * M(loc) ^ 2) ^ -.12; % film coefficient correction factor (Huzel & Huang 86).
    h_g = (.026 / D_t ^ .2) * (mu(loc) ^ .2 * cp(loc) / Pr_gas(loc) ^ .6) * (P_c_max * g / c_star) ^ .8 * (D_t / R_of_curve) ^ .1 * (A_t / A_t) ^ .9 * sigma; % film coefficient - bartz equation (Huzel & Huang 86).
    r = Pr_gas(loc) ^ (1 / 3); 
    Tr = T_c(loc) * (1 + (gamma(loc) - 1) / 2 * r * M(loc) ^ 2); % [F]
    qdotG(i) = h_g * (Tr - T_wg(i)); % [BTU/s-in^2]
    T_wl(i) = T_wg(i) - qdotG(i) * t_w / kw; % [F]

    % Liquid Side
    visc_fuel = py.CoolProp.CoolProp.PropsSI('V','T', (fuel_temp(i-1) + 459.67) * u.R2K,'P', fuel_pressure(i-1) * u.PSI2PA,'C3H8') * (1.450E-4); % [psi-s]
    visc_surface = py.CoolProp.CoolProp.PropsSI('V','T', (T_wl(i) + 459.67) * u.R2K,'P', fuel_pressure(i-1) * u.PSI2PA,'C3H8') * (1.450E-4); % [psi-s]
    cp_fuel = py.CoolProp.CoolProp.PropsSI('C' , 'T', (fuel_temp(i-1) + 459.67) * u.R2K, 'P', fuel_pressure(i-1) * u.PSI2PA, 'C3H8') / (4184); % [BTU/lb-F] 
    k_fuel = py.CoolProp.CoolProp.PropsSI('L', 'T', (fuel_temp(i-1) + 459.67) * u.R2K, 'P', fuel_pressure(i-1) * u.PSI2PA, 'C3H8') * (0.27733887194); % [BTU/s-in-F]
    
    reynolds = (4 * mdotchan) / (pi * hydraulic_D * visc_fuel);
    prandtl = (cp_fuel * visc_fuel) / k_fuel;    
    nusselt = 0.027 * (reynolds ^ (4/5)) * (prandtl ^ (1/3)) * (visc_fuel / visc_surface ^ 0.14);
    h_l = (nusselt * k_fuel) / hydraulic_D; 

    qdotL(i) = h_l * (T_wl(i) - fuel_temp(i-1)); % [BTU/s-in^2]

    % Heat flux check
    if abs(qdotG(i) - qdotL(i)) > qdotTolerance
        if qdotG(i) - qdotL(i) > 0
            T_wg(i) = T_wg(i) + step;
        else 
            T_wg(i) = T_wg(i) - step;
        end 
        step = step / 2;
        iter = iter + 1;
    else 
        fuel_temp(i) = fuel_temp(i-1) + 1 / (mdotchan * cp_fuel) * qdotG(i) * area; 
        %pressure(i) = pressure(i-1) + 
        fprintf("Gas Side Wall Temp (F): %0.2f\n", T_wg(i))

        i = i + 1;
        step = 1000;
        qdotG(i) = qdotG(i-1);
    end
end






% 
% 
%     %% CEA Inputs
%     % initial CEA run to find throat conditions
%     [~, ~, ~, M, gamma, P, T, rho, mu, Pr_gas, Mw, k, son, cp] = RunCEA(P_c, P_e, fuel, fuel_weight, fuel_temp, oxidizer, oxidizer_temp, OF, 0, 0, CEA_input_name, 1, 1);
%     
%     % perform initial heat transfer and structural calculations to find wall thickness
%     q_dot = 
% 
% %% Set inlet properties
% % necessary initial flow properties: m_dot, pressure, temperature (all other fluid properties can be derived from pressure and temperature
% % necessary geometric properties: channel shape (I will kill you if it's anything but a square), channel diameter, wall thickness (calculated via structural limitations)
% % necessary thermal properties: maximum hot wall temperature for your wall material
% 
% max_T_wg = 120; % maximum hot wall temperature [K]
% 
% % calculate number of channels and mass flow rate through each
% num_channels = pi * (D_t + .8 * (D_ch + 2 * t_w)) / (D_ch + 2 * t_w); % number of channels (Heister 206).
% m_dot_CHANNEL = m_dot / num_channels;
% 
% 
% subsonic_area_ratios = (pi * r_contour(x_contour < 0) .^ 2) / A_t;
% supersonic_area_ratios = (pi * r_contour(x_contour > 0) .^ 2) / A_t;
% 
% %% Begin iterative sizing
% % start at manifold and step up along chamber length
% 
% % engine_pos = final_pos
% % for engine_pos ~= final_pos
%     % make T_wg guess (gas-side wall temperature)
% 
%     % calculate h_g (film coefficient) from q_dot = h_g * (T_r - T_wg_guess) - T_r is the "gas temperature" axially along the chamber from CEA
% 
%     %% Initialization
%     stepnum = 100;
%     T_wg_i = 1000; %Initial Guess of Gas side Temperature
%     gasheattransfer = 1000;
%     liqheatransfer = 0;
%     
%     
%     
%     
%     
%     
%     %% Step 2: Calculate Number of channels and channel mass flow rate
%     numchannels = pi * (D_t + 0.8 * (D_t + 2 * t_w)) / (D_t + 2 * t_w); %Number of Channels (EQ 6.30) (Change the coefficient later)
%     mdotchan = mdotf / numchannels; %Mass flow of channel (EQ 6.31)
%     
%     %% Step 3: Begin Stepping Down tube/channel
%     %Property Initializations
% 
%     %Chamber Conditions
%     [~, ~, ~, ~, gamma, P_gas, T_gas, density, mu_gas, Pr_gas, Mw, k, son, cp] ...
%         = RunCEA(P_c, P_e, fuel, fuel_weight, fuel_temp, oxidizer, oxidizer_temp, OF, 0, 0, CEA_input_name, 1, 0);
%     r = Pr_gas .^ (1 / 3); % recovery factor - biased towards larger engines, very small engines should use Pr^.5 (Heister 196).
%     T_r = T_gas .* (1 + r .* (gamma - 1) / 2 * M ^ 2) / (1 * (gamma - 1) / 2 * M .^ 2); % recovery temp (adiabatic wall temp) - corrects for compressible boundry layers (Huzel & Huang 85).
%    
%     %Coolant Conditions
%     fuel_pressure = [fuel_pressure, zeros(1,301)]; %liquid Pressure
%     fuel_temp = [fuel_temp, zeros(1,301)]; %liquid Temperature 
%     %Ref Prop
%     for i = [1:stepsize]
%         liq_mu = exp(3.402 + 0.0132 * fuel_pressure(i) + (957.3 + 3.090 * fuel_pressure(i) -0.0542 * fuel_pressure(i) ^2) / (fuel_temp(i) - 57.35)); % J. Chem. Eng. Data 2022, 67, 9, 2242–2256
%         Pr_liquid = liq_mu * Cp / kc;
%         while liqheattransfer < gasheattransfer * upperbound || liqheattransfer > gasheattransfer * lowerbound
%             % step 5: calculate gas film coefficient and heat transfer 
%             sigma = (.5 * T_wg / T_c * (1 + (gamma(i) - 1) / 2 * M(i) ^ 2) + .5) ^ -.68 * (1 + (gamma(i) - 1) / 2 * M(i) ^ 2) ^ -.12; % film coefficient correction factor (Huzel & Huang 86).
%             h_g = (.026 / D_t ^ .2) * (mu ^ .2 * cp / Pr ^ .6) * (P_c * g / c_star) ^ .8 * (D_t / radius_throat) ^ .1 * (A_t / A_t) ^ .9 * sigma; % film coefficient - bartz equation (Huzel & Huang 86).
%             gasheattransfer = h_g * (T_r - Twgi);  %Gas Heat Transfer (EQ 6.16)
%     
%             %Step 6: Calculate Liquid Wall Temperature from conduction 
%             Twl(i) = gaswalltemp - gasheattrans * t_w / thermconduct; %Liquid Wall Temp (EQ 6.29)
%     
%             %Step 7: Compute Liquid Film Coefficient
%             hl = (a * Re_liquid^m * Pr_liquid^n * (visfree / viscwall)^b) * k / L;    %Liquid Film Coefficient (EQ 6.19) 
%     
%             %Step 8: Compute Heat Flux. Compare it to step 5
%             liqheatransfer = hl * (Twl(i) - fuel_temp(i)); %Liquid Heat Transfer (EQ  6.29)
%     
%             %Step 4: Guess Gass Wall Temperature
%     
%             twg(i) = Tgas(i) - liqheatransfer / hg; %Guess Gass Wall temp using liquid heat transfer value
%     
%             %Step 9: Run loop until step 5/8 get same value for heat flux
%         end
%         %Step 10: Obtain new liquid temperature/pressure
%         fuel_temp(i + 1) = T(i) + 1 / (mdotchan * Cp)* gasheattransfer * chamber_length/stepnum * D_c/numchannels;  %Heister Eq. 6.39 (pg 212) wall_length/stepnum term needs to be fixed % IS IT D_C OR D_T
%         fuel_pressure(i + 1) = fuel_pressure(i) - cf(i) * (chamber_length / (stepnum *chan_diam)) * 2 * liq_density * liq_velocity^2; %Channel Height???
%     
%         %Step 12: Structural Analysis Checks
%         St = .5*(Pl- P_gas)*(width/wallthick)^2 + (E*a*gasheattransfer*wallthick)/(2*(1-v)kw); %Combined tangential stresses: Heister Eq 6.33 page 207
%         Sl = E*a*(Twl-fuel_temp); %Longtudinal thermal stress (Huzel and Huang, EQ 2-28, pg 92) The temperatures used here may not right for determining the delta T in this equation.
%         Sc = 4*Et*Ec*t_w/((((Et)^(1/2))*((Ec)^(1/2))^2)*(3*(1-v^2)*tube_radius)); %Critical Stress Buckling (Huzel and Huang, Eq 4-29, pg 93)
% 
% 
% 
% 
% end
