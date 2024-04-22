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
        
        xGrid
        yGrid
        referenceXY 
        
        apsGrid

    end
    
    methods
        function this = ApsModel2( ~ )
            this.hasFile = true;
            this.filepath = '$WORK$/aps/$id$';
            this.fileextension = 'mat';
        end%ctor

        function interpolatedPhase = interpolate(this, lat, lon, ele, isXY)
            % interpolate(this, lat, lon, ele, isXY)
            % Use isXY to interpolate using the XY grids (meters) instead of 
            % lat/lon
            % lat - latitude or, if isXY, Y
            % lon - longitude or, if isXY, X
            % ele - meters elevation w.r.t. reference point
            % XY is relative to XY of reference point.
            if nargin == 4
                isXY = false;
            end
            
            if isXY
                assert(~(isempty(this.xGrid) || isempty(this.yGrid)) )
            else
                assert(~(isempty(this.lonGrid) || isempty(this.latGrid)) )
            end
            
            for imageIndex = size(this.apsGrid, 3):-1:1
                if isXY
                interpolatedPhase(:,imageIndex) = interp2( this.xGrid, this.yGrid, ...
                    this.apsGrid(:,:,imageIndex), lon(:), lat(:) );
                else
                interpolatedPhase(:,imageIndex) = interp2( this.lonGrid, this.latGrid, ...
                    this.apsGrid(:,:,imageIndex), lon(:), lat(:) );
                end
            end

            % Do elevation-dependent aps if requested
            if nargin > 3 && ~isempty(this.elevationToPhase)
                dEle = ele - this.referenceElevation;
                interpolatedPhase = interpolatedPhase ....
                    .* exp( -1i .* this.elevationToPhase .* dEle );
            end

            % remove reference phase
            interpolatedPhase = interpolatedPhase .* this.referencePointPhase;
        end % interpolate

    end % methods
end % classdef

