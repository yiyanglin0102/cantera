classdef FlowDevice < handle

    properties
        type
        id
        upstream
        downstream
    end

    methods
        %% FlowDevice class constructor

        function x = FlowDevice(typ)
            % FLOWDEVICE  FlowDevice class constructor.
            % x = FlowDevice(typ)
            % Base class for devices that allow flow between reactors.
            % :mat:func:`FlowDevice` objects are assumed to be adiabatic,
            % non-reactive, and have negligible internal volume, so that they are
            % internally always in steady-state even if the upstream and downstream
            % reactors are not. The fluid enthalpy, chemical composition, and mass
            % flow rate are constant across a :mat:func:`FlowDevice`, and the
            % pressure difference equals the difference in pressure between the
            % upstream and downstream reactors.
            %
            % See also: :mat:func:`MassFlowController`, :mat:func:`Valve`
            %
            % :param typ:
            %     Type of :mat:func:`FlowDevice` to be created. ``typ='MassFlowController'``
            %     for :mat:func:`MassFlowController`,  ``typ='PressureController'`` for
            %     :mat:func:`PressureController` and ``typ='Valve'`` for
            %     :mat:func:`Valve`
            % :return:
            %     Instance of class :mat:func:`FlowDevice`
            %
            checklib;

            if nargin == 0
                error('please specify the type of flow device to be created');
            end

            x.type = typ;
            x.id = calllib(ct, 'flowdev_new', typ);
            x.upstream = -1;
            x.downstream = -1;
        end

        %% Utility methods

        function clear(f)
            % CLEAR  Clear the specified flow device from memory.
            % f.clear
            % :param f:
            %     Instance of :mat:func:`FlowDevice` to be cleared.
            %
            calllib(ct, 'flowdev_del', f.id);
        end

        %% FlowDevice methods

        function install(f, upstream, downstream)
            % INSTALL  Install a flow device between reactors or reservoirs.
            % f.install(upstream, downstream)
            % :param f:
            %     Instance of class :mat:func:`FlowDevice` to install
            % :param upstream:
            %     Upstream :mat:func:`Reactor` or :mat:func:`Reservoir`
            % :param downstream:
            %     Downstream :mat:func:`Reactor` or :mat:func:`Reservoir`
            % :return:
            %     Instance of class :mat:func:`FlowDevice`
            %
            if nargin == 3
                if ~isa(upstream, 'Reactor') || ~isa(downstream, 'Reactor')
                    error(['Flow devices can only be installed between',...
                           'reactors or reservoirs']);
                end
                i = upstream.id;
                j = downstream.id;
                calllib(ct, 'flowdev_install', f.id, i, j);
            else error('install requires 3 arguments');
            end
        end

        function mdot = massFlowRate(f)
            % MASSFLOWRATE  Get the mass flow rate.
            % mdot = f.massFlowRate
            % :param f:
            %     Instance of class :mat:func:`MassFlowController`
            % :return:
            %     The mass flow rate through the :mat:func:`FlowDevice` at the current time
            %
            mdot = calllib(ct, 'flowdev_massFlowRate2', f.id);
        end

        function setFunction(f, mf)
            % SETFUNCTION  Set the mass flow rate with class :mat:func:`Func`.
            % f.setFunction(mf)
            %
            % See also: :mat:func:`MassFlowController`, :mat:func:`Func`
            %
            % :param f:
            %     Instance of class :mat:func:`MassFlowController`
            % :param mf:
            %     Instance of class :mat:func:`Func`
            %
            if strcmp(f.type, 'MassFlowController')
                k = calllib(ct, 'flowdev_setTimeFunction', f.id, ...
                            mf.id);
            else
                error('Time function can only be set for mass flow controllers.');
            end
        end

        function setMassFlowRate(f, mdot)
            % SETMASSFLOWRATE  Set the mass flow rate to a constant value.
            % f.setMassFlowRate(mdot)
            %
            % See also: :mat:func:`MassFlowController`
            %
            % :param f:
            %     Instance of class :mat:func:`MassFlowController`
            % :param mdot:
            %     Mass flow rate
            %
            if strcmp(f.type, 'MassFlowController')
                k = calllib(ct, 'flowdev_setMassFlowCoeff', f.id, mdot);
            else
                error('Mass flow rate can only be set for mass flow controllers.');
            end
        end

        function setMaster(f, d)
            % SETMASTER  Set the Master flow device used to compute this device's mass
            % flow rate.
            % f.setMaster(d)
            % :param f:
            %     Instance of class :mat:func:`MassFlowController`
            % :param mf:
            %     Instance of class :mat:func:`Func`
            %
            if strcmp(f.type, 'PressureController')
                k = calllib(ct, 'flowdev_setMaster', f.id, d);
            else
                error('Master flow device can only be set for pressure controllers.');
            end
        end

        function setValveCoeff(f, k)
            % SETVALVECOEFF  Set the valve coefficient :math:`K`.
            % f.setValveCoeff(k)
            % The mass flow rate [kg/s] is computed from the expression
            %
            % .. math:: \dot{m} = K(P_{upstream} - P_{downstream})
            %
            % as long as this produces a positive value.  If this expression is
            % negative, zero is returned.
            %
            % See also: :mat:func:`Valve`
            %
            % :param f:
            %     Instance of class :mat:func:`Valve`
            % :param k:
            %     Value of the valve coefficient. Units: kg/Pa-s
            %
            if ~strcmp(f.type, 'Valve')
                error('Valve coefficient can only be set for valves.');
            end
            ok = calllib(ct, 'flowdev_setValveCoeff', f.id, k);
        end

    end
end