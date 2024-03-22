classdef ApsModel2 < OI.Data.DataObj
    properties
        STACK
        id = 'aps_model_s$STACK$'
        generator = 'ApsKriging2'

        inputPhase
        inputPhaseFilename

        % calibration of input
        referencePointPhase
        referencePointIndex
        referenceTimeSeries
        referenceKFactors

        virtualMasterImage_initial
        temporalCoherence_initial

        virtualMasterImage_working

        % kriging
        variogramStructs

        % Phase w.r.t. elevation
        elevationToPhase
        referenceElevation

        % interpolators
        latGrid
        lonGrid
        apsGrid

    end
    
    methods
        function this = ApsModel2( ~ )
            this.hasFile = true;
            this.filepath = '$WORK$/aps/$id$';
            this.fileextension = 'mat';
        end%ctor

        function interpolatedPhase = interpolate(this, lat, lon, ele)
            for imageIndex = size(this.apsGrid, 3):-1:1
                interpolatedPhase(:,imageIndex) = interp2( this.lonGrid, this.latGrid, ...
                    this.apsGrid(:,:,imageIndex), lon(:), lat(:) );
            end

            % Do elevation-dependent aps if requested
            if nargin > 3
                dEle = ele - this.referenceElevation;
                interpolatedPhase = interpolatedPhase ....
                    .* exp( -1i .* this.elevationToPhase .* dEle );
            end

            % remove reference phase
            interpolatedPhase = interpolatedPhase .* this.referencePointPhase;
        end % interpolate

    end % methods
end % classdef

