function sct_register_SbS(src,dest)
% sct_register_SbS(src,dest)
% example: sct_register_SbS qspace.nii template.nii
[basename,path]=sct_tool_remove_extension(src,1);


% move inputs to temp folder
tmp_folder=sct_tempdir;
sct_gunzip(src,tmp_folder,'src.nii');
sct_gunzip(dest,tmp_folder,'dest.nii');
cd(tmp_folder);

% register
sct_reslice('src.nii', 'dest.nii',0)
sct_unix('sct_image -i dest.nii -setorient RPI -o dest.nii')
sct_unix('sct_register_multimodal -i src_reslice.nii -d dest.nii -iseg src_reslice.nii -dseg dest.nii -param step=1,type=seg,algo=centermassrot,metric=MeanSquares,slicewise=1,smooth=2:step=2,type=im,slicewise=1,algo=affine:step=3,type=im,algo=bsplinesyn,slicewise=1:step=4,type=im,algo=syn,gradStep=0.2,smooth=0.1,metric=CC')
sct_unix('sct_concat_transfo -d dest.nii -w step0/step00GenericAffine.mat,step0/step01Warp.nii.gz,warp_src_reslice2dest.nii.gz -o warp_forward.nii.gz')
sct_unix('sct_concat_transfo -w warp_dest2src_reslice.nii.gz,step0/step01InverseWarp.nii.gz,-step0/step00GenericAffine.mat -d src.nii -o warp_inverse.nii.gz');

cd ../

% bring back results
sct_unix(['mv ' tmp_folder filesep 'src_reslice_reg.nii ' basename '_reg.nii']);
sct_unix(['mv ' tmp_folder filesep 'warp_forward.nii.gz ' path]);
sct_unix(['mv ' tmp_folder filesep 'warp_inverse.nii.gz ' path]);

rmdir(tmp_folder,'s')
disp(['>> unix('' fslview ' basename '_reg.nii ' dest ''')'])
%sct_unix(['fslview ' basename '_reg.nii -b 0,100 ' dest ' -b 0,1 &'])
