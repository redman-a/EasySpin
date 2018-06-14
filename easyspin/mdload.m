%  mdload  Load data generated by molecular dynamics simulations.
%
%   MD = mdload(TrajFile, AtomInfo);
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
%                    ResName    character array
%                               Name of residue assigned to spin label side 
%                               chain, e.g. "CYR1" is the default used by 
%                               CHARMM-GUI.
%
%                    AtomNames  structure array
%                               Contains the atom names used in the PSF to 
%                               refer to the following atoms in the 
%                               nitroxide spin label molecule:
%
%                                   O (ONName)
%                                   |
%                                   N (NNName)
%                                  / \
%                        (C1Name) C   C (C2Name)
%
%     OutOpt         structure array containing the following fields
%
%                    Format    Frame: (default) coordinate frame vector 
%                                trajectories given as output
%                              Dihedrals: spin label side chain dihedrals 
%                                given as output
%
%                    Verbosity 0: no display, 1: show info
%
%
%   Output:
%     MD             structure array containing the following fields:
%
%                    nSteps   integer
%                             total number of steps in trajectory
%
%                    dt       double
%                             size of time step (in s)
%
%                    type     string
%                             'Frame': output of FrameX, FrameY, and FrameZ
%                               each is numeric, size = (nSteps,3)
%                               x,y,z coordinate trajectories for X-axis,
%                               Y-axis, and Z-axis vectors
%                             'Dihedrals': output of chi1, chi2, chi3, chi4, 
%                               and chi5, each is numeric array,
%                               size(nSteps,1), dihedral angles
%                             if not specified, output is Xxyz, a numeric 
%                             array, size = (nSteps,3), x,y,z coordinate 
%                             trajectory for each atom in the spin label
%                             frame

%
%
%   Supported formats are identified via the extension
%   in 'TrajFile' and 'TopFile'. Extensions:
%
%     NAMD, CHARMM:        .DCD, .PSF
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

if ~isfield(OutOpt,'Frame'), OutOpt.Frame = 1; end
if ~isfield(OutOpt,'Verbosity'), OutOpt.Verbosity = 0; end

% supported file types
supportedTrajFileExts = {'.DCD'};
supportedTopFileExts = {'.PSF'};

TopFile = AtomInfo.TopFile;
ResName = AtomInfo.ResName;
AtomNames = AtomInfo.AtomNames;

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
    if exist(TrajFile{k})>0
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

if ~isfield(OutOpt,'Type'), OutOpt.Type = []; end
if OutOpt.Verbosity==1, tic; end
for iTrajFile=1:nTrajFiles
  temp = processMD(TrajFile{iTrajFile}, TopFile, ResName, AtomNames, ExtCombo);
  if iTrajFile==1
    MD = temp;
  else
    % combine trajectories through array concatenation
    if MD.dt~=temp.dt
      error('Time steps of trajectory files are not equal.')
    end
    MD.nSteps = MD.nSteps + temp.nSteps;
    MD.ONxyz = cat(1, MD.ONxyz, temp.ONxyz);
    MD.NNxyz = cat(1, MD.NNxyz, temp.NNxyz);
    MD.C1xyz = cat(1, MD.C1xyz, temp.C1xyz);
    MD.C2xyz = cat(1, MD.C2xyz, temp.C2xyz);
    if ~OutOpt.isFrame
      MD.C1Rxyz = cat(1, MD.C1Rxyz, temp.C1Rxyz);
      MD.C2Rxyz = cat(1, MD.C2Rxyz, temp.C2Rxyz);
      MD.C1Lxyz = cat(1, MD.C1Lxyz, temp.C1Lxyz);
      MD.S1Lxyz = cat(1, MD.S1Lxyz, temp.S1Lxyz);
      MD.SGxyz = cat(1, MD.SGxyz, temp.SGxyz);
      MD.CBxyz = cat(1, MD.CBxyz, temp.CBxyz);
      MD.CAxyz = cat(1, MD.CAxyz, temp.CAxyz);
      MD.Nxyz = cat(1, MD.Nxyz, temp.Nxyz);
    end
%     MD.Labelxyz = cat(1, MD.Labelxyz, temp.Labelxyz);
  end
  % this could take a long time, so notify the user of progress
  if OutOpt.Verbosity==1
    updateuser(iTrajFile,nTrajFiles)
  end
end

if ~isempty(OutOpt.Type)
  switch OutOpt.Type
    % give the reference frame coordinate axis vector trajectories as output
  %   idxO = find(find(psf.idx_O&psf.idx_SpinLabel));
  %   idxN = find(find(psf.idx_N&psf.idx_SpinLabel));
  %   idxC1 = find(find(psf.idx_C1&psf.idx_SpinLabel));
  %   idxC2 = find(find(psf.idx_C2&psf.idx_SpinLabel));
  %   
  %   MD.Oxyz = MD.Labelxyz(:,:,idxO);
  %   MD.Nxyz = MD.Labelxyz(:,:,idxN);
  %   MD.C1xyz = MD.Labelxyz(:,:,idxC1);
  %   MD.C2xyz = MD.Labelxyz(:,:,idxC2);
    case 'Frame'
      % N-O bond vector
      NO_vec = MD.ONxyz - MD.NNxyz;

      % N-C1 bond vector
      NC1_vec = MD.C1xyz - MD.NNxyz;

      % N-C2 bond vector
      NC2_vec = MD.C2xyz - MD.NNxyz;

      % Normalize vectors
      NO_vec = NO_vec./sqrt(sum(NO_vec.*NO_vec,2));
      NC1_vec = NC1_vec./sqrt(sum(NC1_vec.*NC1_vec,2));
      NC2_vec = NC2_vec./sqrt(sum(NC2_vec.*NC2_vec,2));

      vec1 = cross(NC1_vec, NO_vec, 2);
      vec2 = cross(NO_vec, NC2_vec, 2);

      MD.FrameZ = (vec1 + vec2)/2;
      MD.FrameZ = MD.FrameZ./sqrt(sum(MD.FrameZ.*MD.FrameZ,2));
      MD.FrameX = NO_vec;
      MD.FrameY = cross(MD.FrameZ, MD.FrameX, 2);

      AtomFieldCell = {'ONxyz','NNxyz','C1xyz','C2xyz','C1Rxyz','C2Rxyz','C1Lxyz',...
                   'S1Lxyz','SGxyz','CBxyz','CAxyz','Nxyz'};

      MD = rmfield(MD, AtomFieldCell);

    %   AtomFieldCell = {'Oxyz','Nxyz','C1xyz','C2xyz'};
    % 
    %   MD = rmfield(MD, AtomFieldCell);
    case 'Dihedrals'

      MD.chi1 = dihedral(MD.Nxyz,MD.CAxyz,MD.CBxyz,MD.SGxyz);
      MD.chi2 = dihedral(MD.CAxyz,MD.CBxyz,MD.SGxyz,MD.S1Lxyz);
      MD.chi3 = dihedral(MD.CBxyz,MD.SGxyz,MD.S1Lxyz,MD.C1Lxyz);
      MD.chi4 = dihedral(MD.SGxyz,MD.S1Lxyz,MD.C1Lxyz,MD.C1Rxyz);
      MD.chi5 = dihedral(MD.S1Lxyz,MD.C1Lxyz,MD.C1Rxyz,MD.C2Rxyz);

      AtomFieldCell = {'ONxyz','NNxyz','C1xyz','C2xyz','C1Rxyz','C2Rxyz','C1Lxyz',...
                   'S1Lxyz','SGxyz','CBxyz','CAxyz','Nxyz'};

      MD = rmfield(MD, AtomFieldCell);
  end
end

end

function Traj = processMD(TrajFile, TopFile, ResName, AtomNames, ExtCombo)
% 

switch ExtCombo
  case '.DCD,.PSF'
    % obtain atom indices of nitroxide coordinate atoms
    psf = md_readpsf(TopFile, ResName, AtomNames);  % TODO perform consistency checks between topology and trajectory files
    % load spin label trajectory
    Traj = md_readdcd(TrajFile, psf.idx_SpinLabel);
    % filter based on atom indices from psf file
%     Traj.Labelxyz = Traj.xyz(:,:,psf.idx_SpinLabel);
    Traj.ONxyz = Traj.xyz(:,:,psf.idx_ON==psf.idx_SpinLabel);
    Traj.NNxyz = Traj.xyz(:,:,psf.idx_NN==psf.idx_SpinLabel);
    Traj.C1xyz = Traj.xyz(:,:,psf.idx_C1==psf.idx_SpinLabel);
    Traj.C2xyz = Traj.xyz(:,:,psf.idx_C2==psf.idx_SpinLabel);
    Traj.C1Rxyz = Traj.xyz(:,:,psf.idx_C1R==psf.idx_SpinLabel);
    Traj.C2Rxyz = Traj.xyz(:,:,psf.idx_C2R==psf.idx_SpinLabel);
    Traj.C1Lxyz = Traj.xyz(:,:,psf.idx_C1L==psf.idx_SpinLabel);
    Traj.S1Lxyz = Traj.xyz(:,:,psf.idx_S1L==psf.idx_SpinLabel);
    Traj.SGxyz = Traj.xyz(:,:,psf.idx_SG==psf.idx_SpinLabel);
    Traj.CBxyz = Traj.xyz(:,:,psf.idx_CB==psf.idx_SpinLabel);
    Traj.CAxyz = Traj.xyz(:,:,psf.idx_CA==psf.idx_SpinLabel);
    Traj.Nxyz = Traj.xyz(:,:,psf.idx_N==psf.idx_SpinLabel);
    % we might not need the full spin label trajectory
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
a1 = a1./sqrt(sum(a1.*a1, 2));
% a2 = traj(:, :, idx_atom3) - traj(:, :, idx_atom2);
a2 = a3Traj - a2Traj;
a2 = a2./sqrt(sum(a2.*a2, 2));
% a3 = traj(:, :, idx_atom3) - traj(:, :, idx_atom4);
a3 = a3Traj - a4Traj;
a3 = a3./sqrt(sum(a3.*a3, 2));

b1 = cross(a2, a3, 2);
b2 = cross(a1, a2, 2);

vec1 = dot(a1, b1, 2);
vec1 = vec1.*sum(a2.*a2, 2).^0.5;
vec2 = dot(b1, b2, 2);

DihedralAngle = atan2(vec1, vec2);

end

% function status = FileExist(FileName)
% 
% 
% 
% end