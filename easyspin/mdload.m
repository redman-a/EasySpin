%  mdload  Load data generated by molecular dynamics simulations.
%
%   MD = mdload(TrajFile, AtomInfo);
%   MD = mdload(TrajFile, AtomInfo, OutOpt);
%
%   Input:
%     TrajFile       character array
%                    Name of trajectory output file.
%
%     AtomInfo       structure array containing the following fields
%
%                    TopFile    character array
%                               Name of topology input file used for 
%                               molecular dynamics simulations.
%
%                    SegName    character array
%                               Name of segment in the topology file
%                               assigned to the spin-labeled protein.
%
%                    ResName    character array
%                               Name of residue assigned to spin label side 
%                               chain, e.g. "CYR1" is the default used by 
%                               CHARMM-GUI.
%
%                    AtomNames  structure array
%                               Contains the atom names used in the PSF to 
%                               refer to the following atoms in the 
%                               nitroxide spin label molecule model:
%
%                                    ON (ONname)
%                                    |
%                                    NN (NNname)
%                                  /   \
%                        (C1name) C1    C2 (C2name)
%                                 |     |
%                       (C1Rname) C1R = C2R (C2Rname)
%                                 |
%                       (C1Lname) C1L
%                                 |
%                       (S1Lname) S1L
%                                /
%                      (SGname) SG
%                               |
%                      (CBname) CB
%                               |
%                   (Nname) N - CA (CAname)
%
%     OutOpt         structure array containing the following fields
%
%                    Verbosity 0: no display, 1: (default) show info
%
%                    keepProtCA  0: (default) delete protein alpha carbon 
%                                   coordinates
%                                1: keep them
%
%
%   Output:
%     MD             structure array containing the following fields:
%
%                    nSteps      integer
%                                total number of steps in trajectory
%
%                    dt          double
%                                size of time step (in s)
%
%                    FrameTraj   numeric array, size = (3,3,nTraj,nSteps)
%                                xyz coordinates of coordinate frame axis
%                                vectors, x-axis corresponds to
%                                FrameTraj(:,1,nTraj,:), y-axis corresponds to
%                                FrameTraj(:,2,nTraj,:), etc.
%
%             FrameTrajwrtProt   numeric array, size = (3,3,nTraj,nSteps)
%                                same as FrameTraj, but with global
%                                rotational diffusion of protein removed
%
%                    RProtDiff   numeric array, size = (3,3,nTraj,nSteps)
%                                trajectories of protein global rotational
%                                diffusion represented by rotation matrices
%
%                    dihedrals   numeric array, size = (5,nTraj,nSteps)
%                                dihedral angles of spin label side chain
%                                bonds
%
%
%   Supported formats are identified via the extension
%   in 'TrajFile' and 'TopFile'. Extensions:
%
%     NAMD, CHARMM:        .DCD, .PSF
%

%

function MD = mdload(TrajFile, AtomInfo, OutOpt)

switch nargin
  case 0
    help(mfilename); return;
  case 2 % TrajFile and AtomInfo specified, initialize Opt
    OutOpt = struct;
  case 3 % TrajFile, AtomInfo, and Opt provided
  otherwise
    error('Incorrect number of input arguments.')
end

% if ~isfield(OutOpt,'Type'), OutOpt.Type = 'Protein+Frame'; end
if ~isfield(OutOpt,'Verbosity'), OutOpt.Verbosity = 1; end
if ~isfield(OutOpt,'keepProtCA'), OutOpt.keepProtCA = 0; end
% OutType = OutOpt.Type;

global EasySpinLogLevel;
EasySpinLogLevel = OutOpt.Verbosity;

% supported file types
supportedTrajFileExts = {'.DCD'};
supportedTopFileExts = {'.PSF'};

if isfield(AtomInfo,'TopFile')
  TopFile = AtomInfo.TopFile;
else
  error('AtomInfo.TopFile is missing.')
end

if isfield(AtomInfo,'ResName')
  ResName = AtomInfo.ResName;
else
  error('AtomInfo.ResName is missing.')
end

if isfield(AtomInfo,'AtomNames')
  AtomNames = AtomInfo.AtomNames;
else
  error('AtomInfo.AtomNames is missing.')
end

if isfield(AtomInfo,'SegName')
  SegName = AtomInfo.SegName;
else
  error('AtomInfo.SegName is missing.')
end

if ~ischar(TopFile)||regexp(TopFile,'\w+\.\w+','once')<1
  error('TopFile must be given as a character array, including the filename extension.')
end

% if numel(regexp(TopFile,'\.'))>1
%   error('Only one period (".") can be included in TopFile as part of the filename extension. Remove the others.')
% end

if exist(TopFile,'file')>0
  [TopFilePath, TopFileName, TopFileExt] = fileparts(TopFile);
  TopFile = fullfile(TopFilePath, [TopFileName, TopFileExt]);
else
  error('TopFile "%s" could not be found.', TopFile)
end

if ischar(TrajFile)
  % single trajectory file
  
  if exist(TrajFile,'file')>0
    % extract file extension and file path
    [TrajFilePath, TrajFileName, TrajFileExt] = fileparts(TrajFile);
    % add full file path to TrajFile
    TrajFile = fullfile(TrajFilePath, [TrajFileName, TrajFileExt]);
  else
    error('TrajFile "%s" could not be found.', TrajFile)
  end
  
  TrajFile = {TrajFile};
  TrajFilePath = {TrajFilePath};
  TrajFileExt = {TrajFileExt};
  nTrajFiles = 1;
elseif iscell(TrajFile)
  % multiple trajectory files
  if ~all(cellfun('isclass', TrajFile, 'char'))
    error('If TrajFile is a cell array, each element must be a character array.')
  end
  nTrajFiles = numel(TrajFile);
  TrajFilePath = cell(nTrajFiles,1);
  TrajFileName = cell(nTrajFiles,1);
  TrajFileExt = cell(nTrajFiles,1);
  for k=1:nTrajFiles
    if exist(TrajFile{k},'File')>0
      [TrajFilePath{k}, TrajFileName{k}, TrajFileExt{k}] = fileparts(TrajFile{k});
      TrajFile{k} = fullfile(TrajFilePath{k}, [TrajFileName{k}, TrajFileExt{k}]);
    else
      error('TrajFile "%s" could not be found.', TrajFile{k})
    end
  end
  % make sure that all file extensions are identical
  if ~all(strcmp(TrajFileExt,TrajFileExt{1}))
    error('At least two of the TrajFile file extensions are not identical.')
  end
  if ~all(strcmp(TrajFilePath,TrajFilePath{1}))
    error('At least two of the TrajFilePath locations are not identical.')
  end
else
  error(['Please provide ''TrajFile'' as a single character array ',...
         '(single trajectory file) or a cell array whose elements are ',...
         'character arrays (multiple trajectory files).'])
end

TrajFileExt = upper(TrajFileExt{1});
TopFileExt = upper(TopFileExt);

% check if file extensions are supported

if ~any(strcmp(TrajFileExt,supportedTrajFileExts))
  error('The TrajFile extension "%s" is not supported.', TrajFileExt)
end

if ~any(strcmp(TopFileExt,supportedTopFileExts))
  error('The TopFile extension "%s" is not supported.', TopFileExt)
end

ExtCombo = [TrajFileExt, ',', TopFileExt];

logmsg(1,'-- extracting data from MD trajectory files -----------------------------------------');

if OutOpt.Verbosity==1, tic; end

% parse through list of trajectory output files
for iTrajFile=1:nTrajFiles
  [temp,psf] = processMD(TrajFile{iTrajFile}, TopFile, SegName, ResName, AtomNames, ExtCombo);
  if iTrajFile==1
    MD = temp;
  else
    % combine trajectories through array concatenation
    if MD.dt~=temp.dt
      error('Time steps of trajectory files %s and %s are not equal.',TrajFile{iTrajFile},TrajFile{iTrajFile-1})
    end
    MD.nSteps = MD.nSteps + temp.nSteps;
    MD.ProtCAxyz = cat(1, MD.ProtCAxyz, temp.ProtCAxyz);
    MD.Labelxyz = cat(1, MD.Labelxyz, temp.Labelxyz);
  end
  % this could take a long time, so notify the user of progress
  if OutOpt.Verbosity
    updateuser(iTrajFile,nTrajFiles)
  end
end

clear temp

% initialize big arrays here for efficient memory usage
MD.FrameTraj = zeros(MD.nSteps,3,3);
MD.FrameTrajwrtProt = zeros(3,3,1,MD.nSteps);
MD.dihedrals = zeros(MD.nSteps,5);

% filter out spin label atomic coordinates
ONxyz = MD.Labelxyz(:,:,psf.idx_ON);
NNxyz = MD.Labelxyz(:,:,psf.idx_NN);
C1xyz = MD.Labelxyz(:,:,psf.idx_C1);
C2xyz = MD.Labelxyz(:,:,psf.idx_C2);
C1Rxyz = MD.Labelxyz(:,:,psf.idx_C1R);
C2Rxyz = MD.Labelxyz(:,:,psf.idx_C2R);
C1Lxyz = MD.Labelxyz(:,:,psf.idx_C1L);
S1Lxyz = MD.Labelxyz(:,:,psf.idx_S1L);
SGxyz = MD.Labelxyz(:,:,psf.idx_SG);
CBxyz = MD.Labelxyz(:,:,psf.idx_CB);
CAxyz = MD.Labelxyz(:,:,psf.idx_CA);
Nxyz = MD.Labelxyz(:,:,psf.idx_N);

MD = rmfield(MD,'Labelxyz');

% calculate frame vectors
% -------------------------------------------------------------------------

% N-O bond vector
NO_vec = ONxyz - NNxyz;

% N-C1 bond vector
NC1_vec = C1xyz - NNxyz;

% N-C2 bond vector
NC2_vec = C2xyz - NNxyz;

% Normalize vectors
NO_vec = bsxfun(@rdivide,NO_vec,sqrt(sum(NO_vec.*NO_vec,2)));
NC1_vec = bsxfun(@rdivide,NC1_vec,sqrt(sum(NC1_vec.*NC1_vec,2)));
NC2_vec = bsxfun(@rdivide,NC2_vec,sqrt(sum(NC2_vec.*NC2_vec,2)));

% z-axis
vec1 = cross(NC1_vec, NO_vec, 2);
vec2 = cross(NO_vec, NC2_vec, 2);
MD.FrameTraj(:,:,3) = vec1 + vec2;
MD.FrameTraj(:,:,3) = bsxfun(@rdivide,MD.FrameTraj(:,:,3),sqrt(sum(MD.FrameTraj(:,:,3).*MD.FrameTraj(:,:,3),2)));

% x-axis
MD.FrameTraj(:,:,1) = NO_vec;

% y-axis
MD.FrameTraj(:,:,2) = cross(MD.FrameTraj(:,:,3), MD.FrameTraj(:,:,1), 2);

MD.FrameTraj = permute(MD.FrameTraj, [2, 3, 4, 1]);

% calculate side chain dihedral angles
% -------------------------------------------------------------------------

MD.dihedrals(:,1) = dihedral(Nxyz,CAxyz,CBxyz,SGxyz);
MD.dihedrals(:,2) = dihedral(CAxyz,CBxyz,SGxyz,S1Lxyz);
MD.dihedrals(:,3) = dihedral(CBxyz,SGxyz,S1Lxyz,C1Lxyz);
MD.dihedrals(:,4) = dihedral(SGxyz,S1Lxyz,C1Lxyz,C1Rxyz);
MD.dihedrals(:,5) = dihedral(S1Lxyz,C1Lxyz,C1Rxyz,C2Rxyz);

MD.dihedrals = permute(MD.dihedrals,[2,3,1]);

clear C1Lxyz C1Rxyz C1xyz C2Rxyz C2xyz CAxyz CBxyz NNxyz Nxyz ONxyz S1Lxyz SGxyz
clear NO_vec NC1_vec NC2_vec vec1 vec2

logmsg(1,'-- removing protein global diffusion -----------------------------------------');

% remove global diffusion of protein
% -------------------------------------------------------------------------

% find rotation matrix to align protein alpha carbons with inertia 
% tensor in first snapshot
[RAlign, MD.ProtCAxyz] = orientproteintraj(MD.ProtCAxyz);
qAlign = rotmat2quat(RAlign);

MD.ProtCAxyz = permute(MD.ProtCAxyz,[2,3,1]);

% find optimal rotation matrices and quaternions
RRot = zeros(3,3,MD.nSteps-1);
qRot = zeros(4,MD.nSteps-1);

MD.RProtDiff = zeros(3,3,MD.nSteps);
MD.RProtDiff(:,:,1) = eye(3);

qTraj = zeros(4,MD.nSteps);
qTraj(:,1) = [1;0;0;0];

nAtoms = size(MD.ProtCAxyz,2);
mass = ones(nAtoms,1);

ProtCAxyzInt = zeros(3, nAtoms, MD.nSteps);
ProtCAxyzInt(:,:,1) = MD.ProtCAxyz(:,:,1);

MD.FrameTrajwrtProt(:,:,:,1) = MD.FrameTraj(:,:,:,1);

% LabelFrameInt = zeros(3, nAtoms, MD.nSteps);
% LabelFrameInt(:,:,:,1) = MD.FrameTraj(:,:,:,1);

tic
% for iStep = 2:MD.nSteps
%   LastProtFrameInt = squeeze(ProtCAxyzInt(:,:,iStep-1));
%   ThisProtFrame = MD.ProtCAxyz(:,:,iStep);
% 
%   q = calcbestq(LastProtFrameInt, ThisProtFrame, mass.');
%   R = quat2rotmat(q);
% 
%   ProtCAxyzInt(:,:,iStep) = R.'*ThisProtFrame;  % "internal" Eckart frame
%   MD.FrameTrajwrtProt(:,:,:,iStep) = R.'*MD.FrameTraj(:,:,:,iStep);
% 
%   qRot(:,iStep-1) = q;
%   RRot(:,:,iStep-1) = R;
% 
%   MD.RProtDiff(:,:,iStep) = R*MD.RProtDiff(:,:,iStep-1);
%   qTraj(:,iStep) = quatmult(q, qTraj(:,iStep-1));
% 
%   updateuser(iStep, MD.nSteps)
% end
FirstFrame = MD.ProtCAxyz(:,:,1);
for iStep = 2:MD.nSteps
  
  ThisProtFrame = MD.ProtCAxyz(:,:,iStep);

  q = calcbestq(FirstFrame, ThisProtFrame, mass.');
  R = quat2rotmat(q);

  MD.ProtCAxyz(:,:,iStep) = R.'*ThisProtFrame;
  MD.FrameTrajwrtProt(:,:,:,iStep) = R.'*MD.FrameTraj(:,:,:,iStep);

  qRot(:,iStep-1) = q;
  RRot(:,:,iStep-1) = R;

  MD.RProtDiff(:,:,iStep) = R*MD.RProtDiff(:,:,iStep-1);
  qTraj(:,iStep) = quatmult(q, qTraj(:,iStep-1));

  updateuser(iStep, MD.nSteps)
end

if ~OutOpt.keepProtCA
  % we don't need this anymore and it could be huge
  MD = rmfield(MD,'ProtCAxyz');
end

% logmsg(1,'-- estimating protein global diffusion tensor -----------------------------------------');

% % estimate global diffusion tensor of protein
% % -------------------------------------------------------------------------
% 
% dt = 2.5*MD.dt;  % NOTE: this assumes a solvent-exposed labeling site with 
%                  % a TIP3P water model
% 
% % calculate Cartesian angular velocity components in molecular frame
% wp = q2wp(qRot, dt);
% 
% % cumulative angular displacement
% Deltawp = integral(wp, dt);
% 
% % mean square angular displacement
% msadp = msd_fft(Deltawp);
% msadp = msadp(:, 1:round(end/2));
% 
% tLag = linspace(0, length(msadp)*dt, length(msadp))/1e-12;
% 
% endFit = min(ceil(100e-9/dt), length(msadp));
% 
% pxp = polyfit(tLag(1:endFit), msadp(1,1:endFit), 1);
% pyp = polyfit(tLag(1:endFit), msadp(2,1:endFit), 1);
% pzp = polyfit(tLag(1:endFit), msadp(3,1:endFit), 1);
% 
% MD.DiffGlobal = [pxp(1), pyp(1), pzp(1)]*1e12;

% % find frame trajectory without protein's rotational diffusion
% for iStep = 2:MD.nSteps
%   R = RRot(:,:,iStep);
%   thisStep = MD.FrameTraj(:,:,1,iStep);
%   MD.FrameTrajwrtProt(:,1,1,iStep) = thisStep(:,1).'*R;
%   MD.FrameTrajwrtProt(:,2,1,iStep) = thisStep(:,2).'*R;
%   MD.FrameTrajwrtProt(:,3,1,iStep) = thisStep(:,3).'*R;
% end

end

function [Traj,psf] = processMD(TrajFile, TopFile, SegName, ResName, AtomNames, ExtCombo, OutType)
% 

switch ExtCombo
  case '.DCD,.PSF'
    % obtain atom indices of nitroxide coordinate atoms
    psf = md_readpsf(TopFile, SegName, ResName, AtomNames);  % TODO perform consistency checks between topology and trajectory files
    
    Traj = md_readdcd(TrajFile, psf.idx_ProteinLabel);

    % protein alpha carbon atoms
    Traj.ProtCAxyz = Traj.xyz(:,:,psf.idx_ProteinCA);

    % spin label atoms
    Traj.Labelxyz = Traj.xyz(:,:,psf.idx_SpinLabel);
    
    % remove the rest
    Traj = rmfield(Traj, 'xyz');
  otherwise
    error('TrajFile type "%s" and TopFile "%s" type combination is either ',...
          'not supported or not properly entered. Please see documentation.', TrajFileExt, TopFileExt)
end

end

function updateuser(iter,totN)
% Update user on progress

persistent reverseStr

if isempty(reverseStr), reverseStr = ''; end

avg_time = toc/iter;
secs_left = (totN - iter)*avg_time;
mins_left = floor(secs_left/60);

msg1 = sprintf('Iteration: %d/%d\n', iter, totN);
if avg_time<1.0
  msg2 = sprintf('%2.1f it/s\n', 1/avg_time);
else
  msg2 = sprintf('%2.1f s/it\n', avg_time);
end
msg3 = sprintf('Time left: %d:%2.0f\n', mins_left, mod(secs_left,60));
msg = [msg1, msg2, msg3];

fprintf([reverseStr, msg]);
reverseStr = repmat(sprintf('\b'), 1, length(msg));

end

function DihedralAngle = dihedral(a1Traj,a2Traj,a3Traj,a4Traj)
% function DihedralAngle = dihedral(traj,atomlist)
% calculate dihedral angle given 4 different atom indices and a trajectory
% idx_atom1 = atomlist{1};
% idx_atom2 = atomlist{2};
% idx_atom3 = atomlist{3};
% idx_atom4 = atomlist{4};

% a1 = traj(:, :, idx_atom1) - traj(:, :, idx_atom2);
a1 = a1Traj - a2Traj;
a1 = bsxfun(@rdivide,a1,sqrt(sum(a1.*a1, 2)));
% a2 = traj(:, :, idx_atom3) - traj(:, :, idx_atom2);
a2 = a3Traj - a2Traj;
a2 = bsxfun(@rdivide,a2,sqrt(sum(a2.*a2, 2)));
% a3 = traj(:, :, idx_atom3) - traj(:, :, idx_atom4);
a3 = a3Traj - a4Traj;
a3 = bsxfun(@rdivide,a3,sqrt(sum(a3.*a3, 2)));

b1 = cross(a2, a3, 2);
b2 = cross(a1, a2, 2);

vec1 = dot(a1, b1, 2);
vec1 = vec1.*sum(a2.*a2, 2).^0.5;
vec2 = dot(b1, b2, 2);

DihedralAngle = atan2(vec1, vec2);

end

function [RAlign,traj] = orientproteintraj(traj)
% orient protein along the principal axes of inertia from the first
% snapshot
%

nAtoms = size(traj, 3);
mass = 1;

% subtract by the geometric center
traj = bsxfun(@minus,traj,mean(traj,3));

% calculate the principal axis of inertia for first snapshot
firstStep = squeeze(traj(1,:,:));
x = firstStep(1,:);
y = firstStep(2,:);
z = firstStep(3,:);

I = zeros(3,3);

I(1,1) = sum(mass.*(y.^2 + z.^2));
I(2,2) = sum(mass.*(x.^2 + z.^2));
I(3,3) = sum(mass.*(x.^2 + y.^2));

I(1,2) = - sum(mass.*(x.*y));
I(2,1) = I(1,2);

I(1,3) = - sum(mass.*(x.*z));
I(3,1) = I(1,3);

I(2,3) = - sum(mass.*(y.*z));
I(3,2) = I(2,3);

% scale I for better performance
I = I./norm(I);

[~, ~, a] = svd(I); %a is already sorted by descending order
p_axis = a(:, end:-1:1); %z-axis has the largest inertia
%   p_axis = a;

% check reflection
if det(p_axis) < 0
  p_axis(:,1) = - p_axis(:,1);
end

RAlign = p_axis;

% project onto the principal axis of inertia
for k = 1:nAtoms
  traj(:,:,k) = traj(:,:,k)*RAlign;
end

end

function q = calcbestq(rOld, rNew, mass)
% find the quaternion that best approximates the rotation of the Eckart 
% coordinate frame for a molecule between configurations
%
% Minimizes the following quantity:
%  1/M \sum_\alpha m_\alpha || R(q(n+1))*r_\alpha^int (n) - r_\alpha (n+1) ||^2
%

nAtoms = size(rOld, 2);

if size(rOld,1)~=3 || size(rNew,1)~=3 || nAtoms~=size(rNew,2)
  error('rOld and rNew both must have size (3,nAtoms).')
end

if ~isrow(mass) || size(mass,2)~=nAtoms
  error('mass must be a row vector with length equal to nAtoms.')
end

% rOld = rOld.';
% rNew = rNew.';
% mass = mass.';


% Weighting of coordinates

massTot = sum(mass);

weights = mass/massTot;

left  = rOld.*sqrt(weights);
right = rNew.*sqrt(weights);

M=left*right.';


% Compute optimal quaternion

M = num2cell(M(:));

[Sxx,Syx,Szx,  Sxy,Syy,Szy,   Sxz,Syz,Szz] = M{:};

N=[(Sxx+Syy+Szz), (Syz-Szy),     (Szx-Sxz),      (Sxy-Syx);...
   (Syz-Szy),     (Sxx-Syy-Szz), (Sxy+Syx),      (Szx+Sxz);...
   (Szx-Sxz),     (Sxy+Syx),     (-Sxx+Syy-Szz), (Syz+Szy);...
   (Sxy-Syx),     (Szx+Sxz),     (Syz+Szy),      (-Sxx-Syy+Szz)];

[V,D] = eig(N);

[~, emax] = max(real(diag(D)));
emax = emax(1);

q = real(V(:, emax));  % eigenvector corresponding to maximum eigenvalue

[~,ii] = max(abs(q));
sgn = sign(q(ii(1)));
q = q*sgn;  %Sign ambiguity

% quat = q(:);
% nrm = norm(quat);
% if ~nrm
%  disp 'Quaternion distribution is 0'    
% end
% 
% quat = quat./norm(quat);
% 
% R = quat2rotmat(q);


end

function dy = derivative(y, dt)
  dy = zeros(size(y));
  dy(:,2:end-1) = (y(:,3:end) - y(:,1:end-2));
  dy(:,1) = 4*y(:,2) - 3*y(:,1) - y(:,3);
  dy(:,end) = 3*y(:,end) + y(:,end-2) - 4*y(:,end-1);
  dy = dy./(2*dt);
end

function iy = integral(y, dt)
  iy = zeros(size(y));
  iy(:,1) = 0;
  iy(:,2:end-1) = 5*y(:,1:end-2) + 8*y(:,2:end-1) - y(:,3:end);
  iy(:,end) = -y(:,end-2) + 8*y(:,end-1) + 5*y(:,end);
  iy = cumsum(iy, 2)*dt/12;
end

function w = q2w(qTraj, dt)

dq = derivative(qTraj, dt);

q0 = qTraj(1,:,:);
q1 = qTraj(2,:,:);
q2 = qTraj(3,:,:);
q3 = qTraj(4,:,:);

dq0 = dq(1,:,:);
dq1 = dq(2,:,:);
dq2 = dq(3,:,:);
dq3 = dq(4,:,:);

wx = 2*(-q1.*dq0 + q0.*dq1 - q3.*dq2 + q2.*dq3);
wy = 2*(-q2.*dq0 + q3.*dq1 + q0.*dq2 - q1.*dq3);
wz = 2*(-q3.*dq0 - q2.*dq1 + q1.*dq2 + q0.*dq3);

w = [wx; wy; wz];

end

function wp = q2wp(qTraj, dt)

dq = derivative(qTraj, dt);

q0 = qTraj(1,:,:);
q1 = qTraj(2,:,:);
q2 = qTraj(3,:,:);
q3 = qTraj(4,:,:);

dq0 = dq(1,:,:);
dq1 = dq(2,:,:);
dq2 = dq(3,:,:);
dq3 = dq(4,:,:);

wxp = 2*(-q1.*dq0 + q0.*dq1 + q3.*dq2 - q2.*dq3);
wyp = 2*(-q2.*dq0 - q3.*dq1 + q0.*dq2 + q1.*dq3);
wzp = 2*(-q3.*dq0 + q2.*dq1 - q1.*dq2 + q0.*dq3);

wp = [wxp; wyp; wzp];

end

function msd = msd_fft(x)

if iscolumn(x)
  x = x.';
end

nComps = size(x, 1);
N = length(x);

D = zeros(nComps, N+1);
D(:,2:end) = x.^2;


% D = D.sum(axis=1)
% D = np.append(D,0)
S2 = runprivate('autocorrfft',x, 2, 0, 0, 0);

Q = 2*sum(D, 2);
S1 = zeros(nComps, N);

for m = 1:N
    Q = Q - D(:, m) - D(:, end-m);
    S1(:, m) = Q/((N+1)-m);
end

msd = S1 - 2*S2;

end

%                    Format    'Protein+Frame': (default) xyz coordinates 
%                                of alpha carbon atoms in the protein and 
%                                coordinate frame vector trajectories given
%                                as output
%                              'Frame': coordinate frame vector 
%                                trajectories given as output
%                              'Dihedrals': spin label side chain dihedrals 
%                                given as output

%     switch OutType
%       case 'Protein+Frame'
%       case 'Frame'
%       case 'Dihedrals'

% function status = FileExist(FileName)
% 
% 
% 
% end