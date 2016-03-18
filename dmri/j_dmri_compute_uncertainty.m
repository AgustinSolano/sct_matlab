% =========================================================================
% FUNCTION
% j_dmri_compute_uncertainty.m
%
% Use the output of BedpostX to compute angular maps of 95% uncertainty,
% for the principal diffusion direction.
%
% N.B. If you don't use a 'dmri_struct' structure as input, then YOU SHOULD
% RUN THIS FUNCTION FROM THE .bedpost DIRECTORY!!!
%
% INPUT
% (diff)			structure generated with j_dmri_struct_process_dti.m
% 
% OUTPUT
% (-)
%
% COMMENTS
% Julien Cohen-Adad 2010-01-10
% =========================================================================
% function dmri_struct = j_dmri_compute_uncertainty(dmri_struct)

n				= 2; % number of fibers (1 or 2)
folder_bedpost	= '.bedpostX';
alpha			= 0.05; % P-value for uncertainty map
swap_dim		= 0; % swap X dimension
file_suffixe	= '';
nb_samples		= 0; % if you put 0, it takes all samples generated by BedpostX


disp('COMPUTE ANGULAR UNCERTAINTY')

if ~exist('dmri_struct')
	struct_exists = 0;
	dmri_struct = [];
else
	struct_exists = 1;
end
if ~isfield(dmri_struct,'nex'), dmri_struct.nex = 1; end
if ~isfield(dmri_struct,'folder_average'), dmri_struct.folder_average = {}; end
disp(['-> number of fibers = ',num2str(n)])


for i_nex = 1:dmri_struct.nex

% 	fprintf('\n*** DO PROCESSING FOR NAV=%i\n',i_nex)
	
	j_progress('Load data ...........................................')
	% build folder to bedpostx
	if ~isempty(dmri_struct.folder_average)
		path_bedpost = [dmri_struct.folder_average{i_nex}(1:end-1),folder_bedpost,filesep];
	else
		path_bedpost = [pwd,filesep];
	end		
	j_progress(1)
	
	% loop over fiber (1, 2)
	for iN=1:n
% 		j_cprintf('black','\n')
% 		j_cprintf('-black','Process fiber #%i',iN)
% 		j_cprintf('black','\n')

		% build file names
		file_theta		= ['merged_th',num2str(iN),'samples.nii.gz'];
		file_mean_theta = ['mean_th',num2str(iN),'samples.nii.gz'];
		file_phi		= ['merged_ph',num2str(iN),'samples.nii.gz'];
		file_mean_phi	= ['mean_ph',num2str(iN),'samples.nii.gz'];
		file_mean_ei	= ['ei_mean.nii.gz'];

		% find the number of samples
		[status result] = unix(['fslhd ',path_bedpost,file_theta]);
		ind_dim4 = findstr(result,'dim4           ');
		ind_dim5 = findstr(result,'dim5           ');
		if ~nb_samples
			nb_samples = str2num(result(ind_dim4+15:ind_dim5-1));
		end
		disp(['Number of samples = ',num2str(nb_samples)])
		j_progress(1)

		% Split theta & phi samples
		j_progress('Split theta & phi samples ...........................')	
		cmd = ['fslsplit ',[path_bedpost,file_theta],' tmp_theta -t'];
		unix(cmd);
		j_progress(0.5)
		cmd = ['fslsplit ',[path_bedpost,file_phi],' tmp_phi -t'];
		unix(cmd);
		j_progress(1)
		
		% Convert from Polar to Cartesian
		num = j_numbering(nb_samples,4,0);
		j_progress('Convert from Polar to Cartesian .....................')
		for isample = 1:nb_samples
% 			% split data into one time point
% 			cmd = ['fslroi ',[path_bedpost,file_theta],' theta_tmp ',num2str(isample-1),' 1'];
% 			unix(cmd);
% 			cmd = ['fslroi ',[path_bedpost,file_phi],' phi_tmp ',num2str(isample-1),' 1'];
% 			unix(cmd);
			% convert to Cartesian
			cmd = ['make_dyadic_vectors tmp_theta',num{isample},' tmp_phi',num{isample},' tmp_ei',num{isample}];
			unix(cmd);
			% display progress
			j_progress(isample/nb_samples)
		end
	
		% Convert the mean principal diffusion direction
		cmd = ['make_dyadic_vectors ',path_bedpost,file_mean_theta,' ',path_bedpost,file_mean_phi,' ',file_mean_ei];
		unix(cmd);

		% open mean data
		[ei_mean,dims,scales,bpp,endian] = read_avw(file_mean_ei);
		[nx ny nz nt] = size(ei_mean);
		
		% open the bedpost mask
		mask = read_avw('nodif_brain_mask');
		mask = logical(mask);
		nb_voxels = length(find(mask));
		
		% reshape in 2D to have a nx3 matrix (n = nb of voxels)
		ei_mean_2d = zeros(nb_voxels,3);
		tmp_ei = zeros(nx,ny,nz);
		for iDir=1:3
			tmp_ei = ei_mean(:,:,:,iDir);
			ei_mean_2d(:,iDir) = tmp_ei(mask);
		end
		
		index_nonzero = find(mask);
		ei_err_2d = zeros(nb_voxels,nb_samples);
		
		% Generate distribution of angular error
		j_progress('Generate distribution of angular error ..............')
		for isample = 1:nb_samples
			% open data
			ei = read_avw(['tmp_ei',num{isample},'.nii.gz']);
			% reshape in 2D to have a nx3 matrix (n = nb of voxels)
			ei_2d = zeros(nb_voxels,3);
			tmp_ei = zeros(nx,ny,nz);
			for iDir=1:3
				tmp_ei = ei(:,:,:,iDir);
				ei_2d(:,iDir) = tmp_ei(mask);
			end
			% compute the dot product for each direction and take the inverse
			% cosine to get the angle IN DEGREE between the two vectors.
			% NB: the norm of each vector is assumed to be 1.
			for i_vox = 1:nb_voxels
				ei_err_2d(i_vox,isample) = acos(ei_2d(i_vox,:)*ei_mean_2d(i_vox,:)')*180/pi;
				% check if vectors are not >90� apart
				if (ei_err_2d(i_vox,isample)>90)
					ei_err_2d(i_vox,isample) = 180-ei_err_2d(i_vox,isample);
				end
			end
			% display progress
			j_progress(isample/nb_samples)
		end

		% Compute T-stat from the distribution of angular errors
		j_progress('Compute T-stat from the distribution ................')
		% get T-score at a given P-value
		tail = 2;
		dof = nb_samples;
		criticalT = j_stat_invTcdf(1-alpha/tail,dof);
		% Calculate the standard deviation for each time point
		ei_err_2d_std = zeros(nb_voxels,1);
		criticalAngle_2d = zeros(nb_voxels,1);
		criticalAngle = zeros(nx,ny,nz);
		for i_vox = 1:nb_voxels
			ei_err_2d_std(i_vox) = std(ei_err_2d(i_vox,:));
			j_progress(i_vox/(nb_voxels))
		end
		% compute the critical angular value
		criticalAngle_2d(:,1) = ei_err_2d_std.*criticalT;
		% reshape back
		criticalAngle(mask) = criticalAngle_2d;

		% save image
		j_progress('Save image ........................................')
		save_avw(criticalAngle,[path_bedpost,'uncertainty95_',num2str(iN),file_suffixe,'.nii'],'d',scales)
		j_progress(1)

		% swap dimension because it's all fucked up
		if swap_dim
			cmd = ['export FSLOUTPUTTYPE=NIFTI; fslswapdim uncertainty95_',num2str(iN),file_suffixe,' -x y z uncertainty95_',num2str(iN),file_suffixe];
			[status result] = unix(cmd);
		end
		
		% delete temp images
		j_progress('Delete temporary file ...............................')
		delete tmp*
		j_progress(1)
	end %iN
	
	% save structure
% 	if struct_exists
% 		dmri_struct.fname_uncertainty{i_nex} = [path_bedpost,'uncertainty95.nii.gz'];
% 		save([dmri_struct.path,filesep,'dmri_struct'],'dmri_struct');
% 	end
end

