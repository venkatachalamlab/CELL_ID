classdef NeuroPALImage
    %NEUROPALIMAGE Convert various image formats to a NeuroPAL format.
    %
    %   NeuroPAL files contain 4 variable:
    %      data = the image data (x,y,z,c)
    %      info = the image information
    %           scale = pixel scale in microns (x,y,z)
    %           RGBW = the (R,G,B,W) color channel indices (nan = no data)
    %           GFP = the GFP color channel index(s) (can be empty)
    %           DIC = the DIC channel index (can be empty)
    %           gamma = the gamma correction for the image
    %      prefs = the user preferences
    %           RGBW = the (R,G,B,W) color channel indices (nan = no data)
    %           GFP = the GFP color channel index(s) (can be empty)
    %           DIC = the DIC channel index (can be empty)
    %           gamma = the gamma correction for the image
    %           rotate.horizontal = rotate horizontal?
    %           rotate.vertical = rotate vertical?
    %      worm = the worm information
    %           body = 'Whole Worm', 'Head', 'Midbody', 'Anterior Midbody'.
    %                  'Central Midbody', 'Posterior Midbody', or 'Tail'
    %           age = 'Adult', 'L4', L3', 'L2, 'L1', or '3-Fold'
    %           sex = 'XX' or 'XO'
    %           strain = strain name
    %           notes = experimental notes
    %      mp = matching pursuit (neuron detection) parameters
    %      neurons = the neurons in the image
    
    
    %% Public methods.
    methods (Static)
        function [data, info, prefs, worm, mp, neurons, np_file, id_file] = open(file)
            %OPEN Open an image in NeuroPAL format.
            %
            % Input:
            %   file = the NeuroPAL format filename
            %
            % Output:
            %   data = the image data
            %   info = the image information
            %   prefs = the user preferences
            %   worm = the worm information
            %   mp = matching pursuit (neuron detection) parameters
            %   neurons = the neurons in the image
            %	np_file = the NeuroPAL image file
            %	id_file = the NeuroPAL ID file

            % Initialize the packages.
            import DataHandling.*;

            % Is the user accidentally trying to open the ID file?
            id_file_ext = '_ID.mat';
            if endsWith(file, id_file_ext)
                file = strrep(file, id_file_ext, '.mat');
            end
            
            % Get the file extension.
            [~, ~, ext] = fileparts(file);
            if isempty(ext)
                error('Unknown image format: "%s"', file);
            end
            ext = lower(ext);
            
            % Determine the NeuroPAL filename.
            np_file = strrep(file, ext, '.mat');
            
            % Is the file already in NeuroPAL format?
            if ~exist(np_file,'file')
                switch lower(ext)
                    case '.mat' % NeuroPAL format
                        error('File not found: "%s"', file);
                    case '.czi' % Zeiss format
                        NeuroPALImage.convertCZI(file);
                    case '.nd2' % Nikon format
                        NeuroPALImage.convertND2(file);
                    case {'.lif'} % Leica format
                        NeuroPALImage.convertAny(file);
                    case {'.ims'} % Imaris format
                        NeuroPALImage.convertAny(file);
                    case {'.tif','.tiff'} % TIFF format
                        NeuroPALImage.convertAny(file);
                    case {'.h5'} % Vlab format
                        NeuroPALImage.convertAny(file);   
                    otherwise % Unknown format
                        error('Unknown image format: "%s"', file);
                end
            end
            
            % Did we manage to convert the file?
            if ~exist(np_file,'file')
                error('Cannot read/convert: "%"', np_file);
            end
            
            % Load the file.
            [data, info, prefs, worm, mp, neurons, id_file] = ...
                NeuroPALImage.loadNP(np_file);
        end
    end
    
    
    %% Private variables.
    properties (Constant, Access = private)

        % Default gamma values.
        gamma_default = 1;
        CZI_gamma_default = 0.5;
    end
    
    
    %% Private methods.
    methods (Static, Access = private)
        
        function [data, info, prefs, worm, mp, neurons, id_file] = loadNP(image_file)
            %LOADNP Load an image in NeuroPAL format.
            %
            % Input:
            %   image_file = the NeuroPAL image filename
            %
            % Output:
            %   id_file = the NeuroPAL ID filename
            %   data = the image data
            %   info = the image information
            %   prefs = the user preferences
            %   worm = the worm information
            %   mp = matching pursuit (neuron detection) parameters
            %   neurons = the neurons in the image
            
            % Initialize the packages.
            import Program.*;
            import DataHandling.*;
            
            % Open the image file.
            np_data = load(image_file);
            if ~isfield(np_data, 'data') || ...
                    ~isfield(np_data, 'info') || ...
                    ~isfield(np_data, 'prefs')
                error('Misformatted NeuroPAL file: "%s"', image_file);
            end
            
            % Setup the image file contents.
            data = np_data.data;
            info = np_data.info;
            prefs = np_data.prefs;
            worm = [];
            if isfield(np_data, 'worm')
                worm = np_data.worm;
            end
            
            % Get the image file version.
            version = 0;
            if isfield(np_data, 'version')
                version = np_data.version;
            end
            
            % Check the image file version.
            if version < 1
                
                % Correct the worm info.
                worm.body = prefs.body_part;
                worm.age = 'Adult';
                worm.sex = 'XX';
                worm.strain = '';
                worm.notes = '';
                prefs = rmfield(prefs, 'body_part');
                
                % Update the file version.
                version = ProgramInfo.version;
                save(image_file, 'version', 'prefs', 'worm', '-append');
            end
            
            % Open the ID file.
            version = 0;
            mp = [];
            mp.hnsz = round(round(3./info.scale')/2)*2+1;
            mp.k = 0;
            mp.exclusion_radius = 1.5;
            mp.min_eig_thresh = 0.1;
            sp = [];
            neurons = [];
            id_file = strrep(image_file, '.mat', '_ID.mat');
            if exist(id_file, 'file')
                
                % Load the neurons file.
                id_data = load(id_file);
                
                % Get the ID file version.
                if isfield(id_data, 'version')
                    version = id_data.version;
                end
                
                % Setup the file contents.
                mp = id_data.mp_params;

                % Check the ID file version.
                % Version > 1.
                if version > 1
                    neurons = id_data.neurons;
                    
                % Version 1.
                elseif version == 1
                    
                    % Create the neurons.
                    sp = id_data.sp;
                    neurons = Neurons.Image(sp, worm.body, 'scale', info.scale);
                    
                    % Update the file version.
                    version = ProgramInfo.version;
                    mp_params = mp;
                    save(id_file, 'version', 'neurons', 'mp_params');
                
                % No version.
                elseif version < 1
                    
                    % Are there any neurons?
                    sp = id_data.sp;
                    if ~isempty(sp)
                        
                        % Correct the neuron colors.
                        if ~isfield(sp, 'color_readout')
                            
                            % Set the neuron patch size.
                            patch_hsize = [3,3,0];
                            
                            % Compute the data.
                            data_RGBW = double(data(:,:,:,prefs.RGBW));
                            data_zscored = ...
                                Methods.Preprocess.zscore_frame(double(data_RGBW));
                            
                            % Read the patch colors.
                            num_neurons = size(sp.color,1);
                            sp.color_readout = nan(num_neurons,4);
                            for i = 1:num_neurons
                                patch = Methods.Utils.subcube(data_zscored, ...
                                    round(sp.mean(i,:)), patch_hsize);
                                sp.color_readout(i,:) = ...
                                    nanmedian(reshape(patch, ...
                                    [numel(patch)/size(patch, 4), size(patch, 4)]));
                            end
                        end
                        
                        % Clean up the old sp fields.
                        if isfield(sp, 'mean')
                            sp.positions = sp.mean;
                            sp.covariances = sp.cov;
                            sp = rmfield(sp, {'mean', 'cov'});
                        end
                    end
                    
                    % Create the neurons.
                    neurons = Neurons.Image(sp, worm.body, 'scale', info.scale);
                    
                    % Clean up the old mp fields.
                    if ~isfield(mp, 'exclusion_radius')
                        old_mp = mp;
                        mp  = [];
                        mp.hnsz = old_mp.hnsz;
                        mp.k = old_mp.k;
                        mp.exclusion_radius = 1.5;
                        mp.min_eig_thresh = 0.1;
                    end
                    mp_params = mp;
                    
                    % Update the file version.
                    version = ProgramInfo.version;
                    save(id_file, 'version', 'neurons', 'mp_params');
                end
            end
        end
        
        function np_file = convertCZI(czi_file)
            %CONVERTCZI Convert a CZI file to NeuroPAL format.
            %
            % czi_file = the CZI file to convert
            % np_file = the NeuroPAL format file
            
            % Initialize the packages.
            import Program.*;
            import DataHandling.*;
            
            % Open the file.
            np_file = [];
            [image_data, ~] = DataHandling.imreadCZI(czi_file);
            
            % Check the image orientation.
            data = image_data.data;
            data_order = 1:ndims(data);
            if size(data,1) > size(data,2)
                
                % Fix the orientation.
                data_order(1) = 2;
                data_order(2) = 1;
                data = permute(data, data_order);
                
                % Reorder the image scale.
                scale = image_data.scale;
                image_data.scale(1) = scale(2);
                image_data.scale(2) = scale(1);
            end
            
            % Setup the NP file data.
            info.file = czi_file;
            info.scale = image_data.scale * 1000000; % convert to microns
            info.DIC = image_data.dicChannel;
            
            % Determine the color channels.
            colors = image_data.colors;
            colors = round(colors/max(colors(:)));
            info.RGBW = nan(4,1);
            info.GFP = nan;
            for i = 1:size(colors,1)
                switch char(colors(i,:))
                    case [1,0,0] % red
                        info.RGBW(1) = i;
                    case [0,1,0] % green
                        info.RGBW(2) = i;
                    case [0,0,1] % blue
                        info.RGBW(3) = i;
                    case [1,1,1] % white
                        if i ~= info.DIC
                            info.RGBW(4) = i;
                        end
                    otherwise % GFP
                        info.GFP = i;
                end
            end
            
            % Did we find the GFP channel?
            if isnan(info.GFP) && size(colors,1) > 4
                
                % Assume the first unused channel is GFP.
                unused = setdiff(1:size(colors,1), info.RGBW);
                info.GFP = unused(1);
            end
            
            % Determine the gamma.
            %info.gamma = 1;
            %keys = lower(meta_data.keys);
            %gamma_i = find(contains(keys, 'gamma'),1);
            %if ~isempty(gamma_i)
            %    info.gamma = str2double(meta_data.values(gamma_i));
            %end
            info.gamma = DataHandling.NeuroPALImage.CZI_gamma_default;
            
            % Initialize the user preferences.
            prefs.RGBW = info.RGBW;
            prefs.DIC = info.DIC;
            prefs.GFP = info.GFP;
            prefs.gamma = info.gamma;
            prefs.rotate.horizontal = false;
            prefs.rotate.vertical = false;
            prefs.z_center = ceil(size(data,3) / 2);
            prefs.is_Z_LR = true;
            prefs.is_Z_flip = true;
            
            % Initialize the worm info.
            worm.body = 'Head';
            worm.age = 'Adult';
            worm.sex = 'XX';
            worm.strain = '';
            worm.notes = '';
                
            % Save the CZI file to our MAT file format.
            np_file = strrep(czi_file, 'czi', 'mat');
            version = ProgramInfo.version;
            save(np_file, 'version', 'data', 'info', 'prefs', 'worm');
        end
        
        function np_file = convertND2(nd2_file)
            %CONVERTND2 Convert an ND2 file to NeuroPAL format.
            %
            % nd2_file = the ND2 file to convert
            % np_file = the NeuroPAL format file
            
            % Initialize the packages.
            import Program.*;
            import DataHandling.*;
            
            % Open the file.
            np_file = [];
            [image_data, ~] = DataHandling.imreadND2(nd2_file);
            
            % Check the image orientation.
            data = image_data.data;
            data_order = 1:ndims(data);
            if size(data,1) > size(data,2)
                
                % Fix the orientation.
                data_order(1) = 2;
                data_order(2) = 1;
                data = permute(data, data_order);
                
                % Reorder the image scale.
                scale = image_data.scale;
                image_data.scale(1) = scale(2);
                image_data.scale(2) = scale(1);
            end
            
            % Setup the NP file data.
            info.file = nd2_file;
            info.scale = image_data.scale;
            info.DIC = image_data.dicChannel;
            
            % Determine the color channels.
            colors = image_data.colors;
            colors = round(colors/max(colors(:)));
            info.RGBW = nan(4,1);
            info.GFP = nan;
            for i = 1:size(colors,1)
                switch char(colors(i,:))
                    case [1,0,0] % red
                        info.RGBW(1) = i;
                    case [0,1,0] % green
                        info.RGBW(2) = i;
                    case [0,0,1] % blue
                        info.RGBW(3) = i;
                    case [1,1,1] % white
                        if i ~= info.DIC
                            info.RGBW(4) = i;
                        end
                    otherwise % GFP
                        info.GFP = i;
                end
            end
            
            % Did we find the GFP channel?
            if isnan(info.GFP) && size(colors,1) > 4
                
                % Assume the first unused channel is GFP.
                unused = setdiff(1:size(colors,1), info.RGBW);
                info.GFP = unused(1);
            end
            
            % Determine the gamma.
            %info.gamma = 1;
            %keys = lower(meta_data.keys);
            %gamma_i = find(contains(keys, 'gamma'),1);
            %if ~isempty(gamma_i)
            %    info.gamma = str2double(meta_data.values(gamma_i));
            %end
            info.gamma = NeuroPALImage.gamma_default;
            
            % Initialize the user preferences.
            prefs.RGBW = info.RGBW;
            prefs.DIC = info.DIC;
            prefs.GFP = info.GFP;
            prefs.gamma = info.gamma;
            prefs.rotate.horizontal = false;
            prefs.rotate.vertical = false;
            prefs.z_center = ceil(size(data,3) / 2);
            prefs.is_Z_LR = true;
            prefs.is_Z_flip = true;
            
            % Initialize the worm info.
            worm.body = 'Head';
            worm.age = 'Adult';
            worm.sex = 'XX';
            worm.strain = '';
            worm.notes = '';
            
            % Save the ND2 file to our MAT file format.
            np_file = strrep(nd2_file, 'nd2', 'mat');
            version = ProgramInfo.version;
            save(np_file, 'version', 'data', 'info', 'prefs', 'worm');
        end
        
        function np_file = convertAny(any_file)
            %CONVERTANY Convert any file to NeuroPAL format.
            %
            % any_file = the ND2 file to convert
            % np_file = the NeuroPAL format file
            
            % Initialize the packages.
            import Program.*;
            import DataHandling.*;
            
            % Open the file.
            np_file = [];
            if strcmp(any_file(end-3:end), '.lif')
                [image_data, ~] = DataHandling.imreadLif(any_file);
            elseif strcmp(any_file(end-2:end), '.h5')
                [image_data, ~] = DataHandling.imreadVlab(any_file);
            else
                [image_data, ~] = DataHandling.imreadAny(any_file);
            end
            
            % Check the image orientation.
            data = image_data.data;
            data_order = 1:ndims(data);
            if size(data,1) > size(data,2)
                
                % Fix the orientation.
                data_order(1) = 2;
                data_order(2) = 1;
                data = permute(data, data_order);
                
                % Reorder the image scale.
                scale = image_data.scale;
                image_data.scale(1) = scale(2);
                image_data.scale(2) = scale(1);
            end
            
            % Setup the NP file data.
            info.file = any_file;
            info.scale = image_data.scale;
            info.DIC = image_data.dicChannel;
            
            % Determine the color channels.
            colors = image_data.colors;
            colors = round(colors/max(colors(:)));
            info.RGBW = nan(4,1);
            info.GFP = nan;
            for i = 1:size(colors,1)
                switch char(colors(i,:))
                    case [1,0,0] % red
                        info.RGBW(1) = i;
                    case [0,1,0] % green
                        info.RGBW(2) = i;
                    case [0,0,1] % blue
                        info.RGBW(3) = i;
                    case [1,1,1] % white
                        if i ~= info.DIC
                            info.RGBW(4) = i;
                        end
                    otherwise % GFP
                        info.GFP = i;
                end
            end
            
            % Did we find the GFP channel?
            if isnan(info.GFP) && size(colors,1) > 4
                
                % Assume the first unused channel is GFP.
                unused = setdiff(1:size(colors,1), info.RGBW);
                info.GFP = unused(1);
            end
            
            % Determine the gamma.
            %info.gamma = 1;
            %keys = lower(meta_data.keys);
            %gamma_i = find(contains(keys, 'gamma'),1);
            %if ~isempty(gamma_i)
            %    info.gamma = str2double(meta_data.values(gamma_i));
            %end
            info.gamma = DataHandling.NeuroPALImage.gamma_default;
            
            % Initialize the user preferences.
            prefs.RGBW = info.RGBW;
            prefs.DIC = info.DIC;
            prefs.GFP = info.GFP;
            prefs.gamma = info.gamma;
            prefs.rotate.horizontal = false;
            prefs.rotate.vertical = false;
            prefs.z_center = ceil(size(data,3) / 2);
            prefs.is_Z_LR = true;
            prefs.is_Z_flip = true;
            
            % Initialize the worm info.
            worm.body = 'Head';
            worm.age = 'Adult';
            worm.sex = 'XX';
            worm.strain = '';
            worm.notes = '';
            
            % Save the file to our MAT file format.
            suffix = strfind(any_file, '.');
            if isempty(suffix)
                suffix = length(any_file);
            end
            np_file = cat(2, any_file(1:(suffix(end) - 1)), '.mat');
            version = ProgramInfo.version;
            save(np_file, 'version', 'data', 'info', 'prefs', 'worm');
        end
    end
end
