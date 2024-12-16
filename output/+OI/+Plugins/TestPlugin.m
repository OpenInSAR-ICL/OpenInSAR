classdef TestPlugin < OI.Plugins.PluginBase
    properties
        inputs = {}
        outputs = {OI.Data.TestDataObjSummary()}
        id = 'TestPlugin'
        exampleIndex
    end % properties
    methods
        function this = TestPlugin( varargin )
            this.isArray = true;
        end
        function this = run( this, engine, varargin )
            if isempty(this.exampleIndex)
                this = this.queue_jobs(engine);
                return;
            end
            % write the output
            myData = OI.Data.TestDataObj().configure('exampleIndex', this.exampleIndex);
            engine.save(myData,this.exampleIndex);
            this.isFinished = true;
        end

        function this = queue_jobs( this, engine, varargin )
            jobCount = 0;

            for ii = 1:10
                if this.get_result(engine, ii).exists()
                    continue
                end
                jobCount = jobCount + 1;
                engine.requeue_job_at_index( ...
                    jobCount, ...
                    'exampleIndex', num2str(ii));
            end % queue_jobs

            if jobCount == 0
                this.isFinished = true;
                engine.save( this.outputs{1} );
            end
        end

        function resultObject = get_result( ~, engine, index )
            resultObject = OI.Data.TestDataObj().configure( 'exampleIndex', index ).identify(engine);
        end
    end
end % classdef