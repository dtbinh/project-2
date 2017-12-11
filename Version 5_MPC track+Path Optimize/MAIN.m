% This GOAL of this project is to ultilize the map and laser scan data to find the obstacle-free optimal path
% and use MPC to tracking the optimal path with obstacle-avoidance
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Using RobotSimulator
clear;
close all;
clc;

% Set robotsimulator and enable function
robotRadius = 0.3;
robot = RobotSimulator();
%%
robot.enableLaser(true);
robot.setRobotSize(robotRadius);
robot.showTrajectory(true);

%% Set start point and goal
% Set START to BEGIN
% startLocation = [2.725 14.08];
startLocation = [2.7 1];
figure(1)
hold all
plot(startLocation(1),startLocation(2),'o')

% Set GOAL to REACH
endLocation = [14.38 2.225];
figure(1)
hold all
plot(endLocation(1),endLocation(2),'x')

%% Set up the inial position and pose
initialOrientation = pi/2;
robotCurrentLocation = startLocation;
robotCurrentPose = [robotCurrentLocation initialOrientation];
robot.setRobotPose(robotCurrentPose);

plan_path=[];

%% Use MPC to do path planing
% Continue use MPC and PRM until reach the goal or hit the obstacle
% Get optimized PRM circle waypoints as z_ref
mapInflated = copy(robot.Map);
inflate(mapInflated,robotRadius);
%% Here is where the map gets inflated
optPRMPoints = getOptimalPRMPoints1(mapInflated,startLocation,endLocation);
%PointNo=2

%% Define 3 walking human obstacles
% These 3 humans will walk linearly between their start and end positions

numHumans = 3;
map = copy(robot.Map);

humansStart = [8.8 2.2; 4 10.9; 2 3];
humansEnd = [12 6.5; 12 10; 5.2 8];
humansMoveDist = [(humansEnd(1,:) - humansStart(1,:))/86;
    (humansEnd(2,:) - humansStart(2,:))/30;
    (humansEnd(3,:) - humansStart(3,:))/50];
humansWalkDirection = [1 1;1 1;1 1];
humansCurPos = humansStart;

% To initialise humans on the map
map = moveHumans(map, humansCurPos, humansCurPos);
robot.Map = map;
robot.setRobotPose(robotCurrentPose);
robot.enableLaser(true);
robot.setRobotSize(robotRadius);
robot.showTrajectory(true);

%%
read=0;
M = [];
while norm(robotCurrentPose(1:2) - endLocation)>0.1
    yalmip('clear')
    N_optPRM=size(optPRMPoints,1);
    dis_optPRM=[];
    for i=1:N_optPRM
        dis_optPRM=[dis_optPRM;norm(robotCurrentPose(1:2)-optPRMPoints(i,:))]
    end
    [dis_min,PointNo]=min(dis_optPRM);
    dis_nextPRM=2;
    if norm(robotCurrentPose(1:2)-optPRMPoints(PointNo,:))<dis_nextPRM
        PointNo=PointNo+1
    end
    if PointNo==N_optPRM+1
        PointNo=N_optPRM;
    end
    if robotCurrentPose(1:2)==read
        PointNo=PointNo-1;
    end
    read=robotCurrentPose(1:2);
    z_ref = optPRMPoints(PointNo,:)
    if PointNo==N_optPRM
        z_ref=endLocation;
        %     else
        %         z_ref = optPRMPoints(PointNo,:)
    end
    
    pose = robot.getRobotPose;
    [range,angle] = robot.getRangeData;
    laser=[range angle];
    %     bb = zeros(21,1);
    %     x = aa(1) + bb;
    %     y = aa(2) + bb;
    %     beta = aa(3) + bb;
    
    %    data=[(180/pi)*theta range (180/pi)*angle (180/pi).*(angle+theta) x+range.*cos(angle+theta) y+range.*sin(angle+theta)];
    % Write laser data and use it in MPC
    
    %     o_data = [];
    %     for i = 1:21
    %       if ~isnan(data(i,2))
    %           o_data = [o_data; data(i,5:6)]; %[range angle]
    %       end
    %     end
    %     obs_ref = [];
    %     % Filter: exlude obstacle data that's 20m farther from robot
    %     for i = 1:size(o_data, 1)
    %         if o_data(i,1)<20
    %             obs_ref = [obs_ref;odata(i,:)]; % [range angle]
    %         end
    %     end
    
    % Using MPC path planer
    robotCurrentPose = robot.getRobotPose;
    [get_path,sol,plotHandles] = mpc_controller(robotCurrentPose,z_ref,laser);
    
    % If the result is not successfully solved, then use the previous ones.
    % And reduce the size if use the previous ones.
    % If the path size too small to use, then use PRM get new plan_path.
    if sol.problem == 0
        plan_path = get_path;
        %     elseif size(plan_path,1) >= 8
        %         plan_path = plan_path(8:end,:);
    else
        % if MPC doesn't solve, then drive to the next optPRM point
        plan_path = optPRMPoints(PointNo:end,:);
        if norm(robotCurrentPose(1:2)-optPRMPoints(PointNo,:))<dis_nextPRM
            plan_path = optPRMPoints(PointNo+1:end,:);
        end
    end
    
    %         Copy the curent path and inflate each occupancy grid
    %         mapInflated = copy(robot.Map);
    %         inflate(mapInflated,robotRadius);
    %
    %         % Using PRM (probolistic roadmap method) to find path
    %         prm = robotics.PRM(mapInflated);
    %         % Set # of random points
    %         prm.NumNodes = 200;
    %         prm.ConnectionDistance = 1;
    %
    %         plan_path = findpath(prm, robotCurrentPose(1:2), endLocation);
    
    %         while isempty(plan_path)
    %             % No feasible path found yet, increase the number of nodes
    %             prm.NumNodes = prm.NumNodes + 50;
    %
    %             % Use the |update| function to re-create the PRM roadmap with the changed
    %             % attribute
    %             update(prm);
    %
    %             % Search for a feasible path with the updated PRM
    %             plan_path = findpath(prm,robotCurrentPose(1:2), endLocation);
    %         end
    
    %     end
    
    figure(1)
    hold all
    plan_path
    plot(plan_path(:,1),plan_path(:,2),'.')
    
    %  Use Pure Pursuit to contorl the car
    controller = robotics.PurePursuit;
    
    % Feed the middle point of plan_path to the pursuit controller
    %     if size(plan_path,1) >= 10
    %         controller.Waypoints = plan_path(1:10,:);
    %     else
    controller.Waypoints = plan_path(1:ceil(end/2),:);
    %     end
    
    % The maximum angular velocity acts as a saturation limit for rotational velocity
    controller.DesiredLinearVelocity = 0.4;
    controller.MaxAngularVelocity = 20;
    
    % As a general rule, the lookahead distance should be larger than the desired
    % linear velocity for a smooth path. The robot might cut corners when the
    % lookahead distance is large. In contrast, a small lookahead distance can
    % result in an unstable path following behavior. A value of 0.6 m was chosen
    % for this example.
    controller.LookaheadDistance = 0.6;
    
    % The controller runs at 10 Hz.
    controlRate = robotics.Rate(10);
    
    % Set conditon for loop leaving
    robotCurrentLocation = robotCurrentPose(1:2);
    robotGoal = controller.Waypoints(end,:);
    distanceToGoal = norm(robotCurrentLocation - robotGoal);
    
    % Drive robot 50 times or close(0.02) to desired path end point
    flag=0;
    while ( distanceToGoal > 0.1 && flag < 30)
        [v, omega] = controller(robot.getRobotPose);
        drive(robot, v, omega);
        robotCurrentPose = robot.getRobotPose;
        distanceToGoal = norm(robotCurrentPose(1:2) - robotGoal);
        flag = flag + 1;
        waitfor(controlRate);
        % saves frame for movie
        M = [M, getframe];
    end
    
    for j=1:4
        humansEndPos = humansCurPos + humansWalkDirection.*humansMoveDist;
        for i=1:numHumans
            pt1 = humansEndPos(i,:);
            pt2 = humansEnd(i,:);
            pt3 = humansStart(i,:);
            if (pdist([pt1;pt2],'euclidean') < 0.03)
                humansWalkDirection(i,:) = -humansWalkDirection(i,:);
            end
            if (pdist([pt1;pt3],'euclidean') < 0.03)
                humansWalkDirection(i,:) = -humansWalkDirection(i,:);
            end
        end
        map = moveHumans(map, humansCurPos, humansEndPos);
        robotCurrentPose = robot.getRobotPose;
        robot.Map = map;
        robot.setRobotPose(robotCurrentPose);
        robot.enableLaser(true);
        robot.setRobotSize(robotRadius);
        robot.showTrajectory(true);
        humansCurPos = humansEndPos;
        M = [M, getframe];
    end    
    
    %drive(robot, v, omega);
    %     for i = 1 : length(plotHandles)
    %         set(plotHandles(i),'Visible','off');
    %     end
    delete(plotHandles)
end
%% write frames as .avi file
% v = VideoWriter('movie.avi');
% open(v);
% for i = 1:length(M);
%     writeVideo(v,M(i));
% end
% close(v);