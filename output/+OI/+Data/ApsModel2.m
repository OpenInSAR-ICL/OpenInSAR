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
        function this = ApsModel( ~ )
            this.hasFile = true;
            this.filepath = '$WORK$/aps/$id$';
            this.fileextension = 'mat';
        end%ctor

        function interpolatedPhase = interpolate(this, lat, lon)
            for imageIndex = size(this.apsGrid, 3)
                interpolatedPhase(:,imageIndex) = interp2( lonGrid, latGrid, ...
                    this.apsGrid(:,:,imageIndex), lon(:), lat(:) );
            end
        end

    end
end

