classdef Domain1D < handle

    properties
        domainID % ID of the domain
        type % Type of the domain
        T % Temperature
        P % Pressure
    end

    methods
        %% Domain1D class constructor.

        function d = Domain1D(a, b, c)
            % DOMAIN1D  Domain1D class constructor.
            % d = Domain1D(a, b, c)
            %
            % :parameter a:
            %    String type of domain. Possible values are:
            %    `StagnationFlow`
            %    `Inlet1D`
            %    `Surf1D`
            %    `Symm1D`
            %    `Outlet1D`
            %    `ReactingSurface`
            %    `Sim1D`
            %    `OutletRes`
            %
            % :param b:
            %     Instance of class :mat:func:`Solution` (for ``a == 1``)
            %     or :mat:func:`Interface` (for ``a == 6``). Not used for
            %     all other valid values of ``a``.
            % :param c:
            %     Integer, either 1 or 2, indicating whether an axisymmetric
            %     stagnation flow or a free flame should be created. If not
            %     specified, defaults to 1. Ignored if ``a != 1``.
            %
            checklib;
            d.domainID = -1;

            if nargin == 1
                if strcmp(a, 'Inlet1D')
                    d.domainID = calllib(ct, 'inlet_new');
                elseif strcmp(a, 'Surf1D')
                    d.domainID = calllib(ct, 'surf_new');
                elseif strcmp(a, 'Symm1D')
                    d.domainID = calllib(ct, 'symm_new');
                elseif strcmp(a, 'Outlet1D')
                    d.domainID = calllib(ct, 'outlet_new');
                elseif strcmp(a, 'OutletRes')
                    d.domainID = calllib(ct, 'outletres_new');
                else
                    error('Not enough arguments for that job number');
                end
            elseif nargin == 2
                % a stagnation flow
                if strcmp(a, 'StagnationFlow')
                    if isa(b, 'Solution')
                        d.domainID = calllib(ct, 'stflow_new', ...
                                           b.tpID, b.kinID, b.trID, 1);
                    else
                        error('Wrong argument type. Expecting instance of class Solution.');
                    end
                elseif strcmp(a, 'ReactingSurface')
                    if isa(b, 'Interface')
                        d.domainID = calllib(ct, 'reactingsurf_new');
                        calllib(ct, 'reactingsurf_setkineticsmgr', ...
                                d.domainID, b.kinID);
                    else
                        error('Wrong argument type. Expecting instance of class Interface.');
                    end
                else
                    error('Wrong object type.');
                end
            elseif nargin == 3
                if strcmp(a, 'StagnationFlow')
                    if isa(b, 'Solution')
                        if strcmp(c, 'AxisymmetricFlow')
                            flowtype = 1;
                        else flowtype = 2;
                        end
                        d.domainID = calllib(ct, 'stflow_new', ...
                                           b.tpID, b.kinID, b.trID, flowtype);
                    else
                        error('Wrong argument type. Expecting instance of class Solution.');
                    end
                else
                    error('Unknown domain type.');
                end
            end
%             if d.domainID < 0
%                 error(geterr);
%             end
            d.type = a;
        end

        %% Utility Methods

        function clear(d)
            % CLEAR  Delete the C++ Domain1D object.
            % d.clear
            % :param d:
            %     Instance of class :mat:func:`Domain1D` (or another
            %     object that derives from Domain1D)
            %
            calllib(ct, 'domain_del', d.domainID);
        end

        function d = disableEnergy(d)
            % DISABLEENERGY  Disable the energy equation.
            % d.disableEnergy
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            %
            disp(' ');
            disp('Disabling the energy equation...');
            calllib(ct, 'stflow_solveEnergyEqn', d.domainID, 0);
        end

        function d = enableEnergy(d)
            % ENABLEENERGY  Enable the energy equation.
            % d.enableEnergy
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            %
            disp(' ');
            disp('Enabling the energy equation...');
            calllib(ct, 'stflow_solveEnergyEqn', d.domainID, 1);
        end

        function d = disableSoret(d)
            % DISABLESORET  Disable the diffusive mass fluxes due to the Soret effect.
            % d.disableSoret
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            %
            disp(' ');
            disp('Disabling the Soret effect...');
            calllib(ct, 'stflow_enableSoret', d.domainID, 0);
        end

        function d = enableSoret(d)
            % ENABLESORET  Enable the diffusive mass fluxes due to the Soret effect.
            % d.enableSoret
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            %
            disp(' ');
            disp('Disabling the Soret effect...');
            calllib(ct, 'stflow_enableSoret', d.domainID, 1);
        end

        %% Domain Get Methods

        function b = bounds(d, component)
            % BOUNDS  Return the (lower, upper) bounds for a solution component.
            % d.bounds(componoent)
            % :param component:
            %    String name of the component for which the bounds are
            %    returned.
            % :return:
            %    1x2 Vector of the lower and upper bounds.
            %
            n = d.componentIndex(component);
            lower = calllib(ct, 'domain_lowerBound', d.domainID, n);
            upper = calllib(ct, 'domain_upperBound', d.domainID, n);
            b = [lower, upper];
        end

        function n = componentIndex(d, name)
            % COMPONENTINDEX  Get the index of a component given its name.
            % n = d.componentIndex(name)
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param name:
            %     String name of the component to look up. If a numeric value
            %     is passed, it will be returned.
            % :return:
            %     Index of the component, or input numeric value.
            %
            if isa(name, 'double')
                n = name;
            else
                n = calllib(ct, 'domain_componentIndex', ...
                            d.domainID, name);
                if n >= 0
                    n = n+1;
                end
            end
            if n <= 0
                error('Component not found');
            end
        end

        function n = componentName(d, index)
            % COMPONENTNAME  Get the name of a component given its index.
            % n = d.componentName(index)
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param index:
            %     Integer or vector of integers of components' names
            %     to get.
            % :return:
            %     Cell array of component names.
            %
            n = length(index);
            s = cell(m);
            for i = 1:n
                id = index(i)-1;
                buflen = calllib(ct, 'domain_componentName', ...
                                 d.domainID, id, 0, 0);
                if buflen > 0
                    aa = char(zeros(1, buflen));
                    [out_buf, aa] = calllib(ct, 'domain_componentName', ...
                                            d.domainID, id, buflen, aa);
                s{i} = aa;
            end
            end
        end

        function i = domainIndex(d)
            % DOMAININDEX  Get the domain index.
            % i = d.domainIndex
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :return:
            %     This function returns an integer flag denoting the location
            %     of the domain, beginning with 1 at the left.
            %
            i = calllib(ct, 'domain_index', d.domainID);
            if i >= 0
                i = i + 1;
            end
            if i <= 0
                error('Domain not found');
            end
        end

        function i = domainType(d)
            % DOMAINTYPE  Get the type of domain.
            % i = d.domainType
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :return:
            %     This function returns an integer flag denoting the domain
            %     type.
            %
            i = calllib(ct, 'domain_type', d.domainID);
        end

        function zz = gridPoints(d, n)
            % Get grid points from a domain.
            % :parameter d:
            %    Instance of class 'Domain1D'.
            % :parameter n:
            %    Optional, vector of grid points to be retrieved.
            % :return:
            %    Vector of grid points.

            if nargin == 1
                np = d.nPoints;
                zz = zeros(1, np);
                for i = 1:np
                    zz(i) = calllib(ct, 'domain_grid', d.domainID, i-1);
                end
            else
                m = length(n);
                zz = zeros(1, m);
                for i = 1:m
                    zz(i) = calllib(ct, 'domain_grid', d.domainID, n(i)-1);
                end
            end
        end

        function a = isFlow(d)
            % ISFLOW  Determine whether a domain is a flow.
            % a = d.isFlow
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :return:
            %     1 if the domain is a flow domain, and 0 otherwise.
            %
            t = d.domainType;
            % See Domain1D.h for definitions of constants.
            if t < 100
                a = 1;
            else a = 0;
            end
        end

        function a = isInlet(d)
            % ISINLET  Determine whether a domain is an inlet.
            % a = d.isInlet
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :return:
            %     1 if the domain is an inlet, and 0 otherwise.
            %
            t = d.domainType;
            % See Domain1D.h for definitions of constants.
            if t == 104
                a = 1;
            else a = 0;
            end
        end

        function a = isSurface(d)
            % ISSURFACE  Determine if a domain is a surface.
            % a = d.isSurface
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :return:
            %     1 if the domain is a surface, and 0 otherwise.
            %
            t = d.domainType;
            % See Domain1D.h for definitions of constants.
            if t == 102
                a = 1;
            else a = 0;
            end
        end

        function mdot = massFlux(d)
            % MASSFLUX  Get the mass flux.
            % mdot = d.massFlux
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :return:
            %     The mass flux in the domain.
            %
            mdot = calllib(ct, 'bdry_mdot', d.domainID);
        end

        function y = massFraction(d, k)
            % MASSFRACTION  Get the mass fraction of a species given its integer index.
            % y = d.massFraction(k)
            % This method returns the mass fraction of species ``k``, where
            % k is the integer index of the species in the flow domain
            % to which the boundary domain is attached.
            %
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param k:
            %     Integer species index
            % :return:
            %     Mass fraction of species
            %
            if d.domainIndex == 0
                error('No flow domain attached!')
            end

            if d.isInlet
                y = calllib(ct, 'bdry_massFraction', d.domainID, k-1);
            else error('Input domain must be an inlet');
            end
        end

        function n = nComponents(d)
            % NCOMPONENTS  Get the number of components.
            % n = d.nComponents
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :return:
            %     Number of variables at each grid point
            %
            n = calllib(ct, 'domain_nComponents', d.domainID);
        end

        function n = nPoints(d)
            % NPOINTS  Get the number of grid points.
            % n = d.nPoints
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :return:
            %     Integer number of grid points.
            %
            n = calllib(ct, 'domain_nPoints', d.domainID);
        end

        function tol = tolerances(d, component)
            % TOLERANCES  Return the (relative, absolute) error tolerances for a
            % solution component.
            % tol = d.tolerances(component)
            % :param component:
            %    String name of the component for which the bounds are
            %    returned.
            % :return:
            %    1x2 Vector of the relative and absolute error tolerances.

            n = d.componentIndex(component);
            rerr = calllib(ct, 'domain_rtol', d.domainID, n);
            aerr = calllib(ct, 'domain_atol', d.domainID, n);
            tol = [rerr, aerr];
        end

        function temperature = get.T(d)
            % GET.T  Get the boundary temperature.
            % temperature = d.T
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :return:
            %     Temperature. Units: K
            %
            temperature = calllib(ct, 'bdry_temperature', d.domainID);
        end

        function pressure = get.P(d)
            % GET.P  Get the boundary pressure.
            % pressure = d.P
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :return:
            %     Pressure. Units: Pa
            %
            pressure = calllibt(ct, 'stflow_pressure', d.domainID);
        end

        %% Domain Set Methods

        function set.T(d, t)
            % SET.T  Set the temperature.
            % d.T = t
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param t:
            %     Temperature to be set. Units: K
            %
            if t <= 0
                error('The temperature must be positive');
            end
            calllib(ct, 'bdry_setTemperature', d.domainID, t);
        end

        function set.P(d, p)
            % SET.P  Set the pressure.
            % d.P = p
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param p:
            %     Pressure to be set. Units: Pa
            %
            if p <= 0
                error('The pressure must be positive');
            end
            calllib(ct, 'stflow_setPressure', d.domainID, p);
        end

        function setBounds(d, component, lower, upper)
            % Set bounds on the solution components.
            % :parameter d:
            %    Instance of class 'Domain1D'.
            % :parameter component:
            %    String, component to set the bounds on.
            % :parameter lower:
            %    Lower bound.
            % :parameter upper:
            %    Upper bound.

            n = d.componentIndex(component);
            calllib(ct, 'domain_setBounds', d.domainID, n-1, lower, upper);
        end

        function setCoverageEqs(d, onoff)
            % SETBOUNDS  Set bounds on the solution components.
            % d.setBounds(component, lower, upper)
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param component:
            %     String, component to set the bounds on
            % :param lower:
            %     Lower bound
            % :param upper:
            %     Upper bound
            %
            if ~strcmp(d.type, 'ReactingSurface')
                error('Wrong domain type. Expected a reacting surface domain.');
            end

            ion = -1;
            if isa(onoff,'char')
                if strcmp(onoff, 'on') || strcmp(onoff, 'yes')
                    ion = 1;
                elseif strcmp(onoff, 'off') || strcmp(onoff, 'no')
                    ion = 0;
                else
                    error(strcat('unknown option: ', onoff))
                end
            elseif isa(onoff, 'numeric')
                ion = onoff;
            end
            calllib(ct, 'reactingsurf_enableCoverageEqs', d.domainID, ion);
        end

        function setFixedTempProfile(d, profile)
            % SETFIXEDTEMPPROFILE  Set a fixed temperature profile.
            % d.setFixedTempProfile(profile)
            % Set the temperature profile to use when the
            % energy equation is not being solved. The profile must be entered
            % as an array of positions / temperatures, which may be in rows or
            % columns.
            %
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param profile:
            %     n x 2 or 2 x n array of ``n`` points at which the temperature
            %     is specified.
            %
            sz = size(profile);
            if sz(1) == 2
                l = length(profile(1, :));
                calllib(ct, 'stflow_setFixedTempProfile', d.domainID, ...
                        l, profile(1, :), l, profile(2, :));
            elseif sz(2) == 2
                l = length(profile(:, 1));
                calllib(ct, 'stflow_setFixedTempProfile', d.domainID, ...
                        l, profile(:, 1), l, profile(:, 2));
            else error('Wrong temperature profile array shape.');
            end
        end

        function setID(d, id)
            % SETID  Set the ID tag for a domain.
            % d.setID(id)
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param id:
            %     String ID to assign
            %
            calllib(ct, 'domain_setID', d.domainID, id);
        end

        function setMdot(d, mdot)
        % SETMDOT  Set the mass flow rate.
        % d.setMdot(mdot)
        % :param d:
        %     Instance of class :mat:func:`Domain1D`
        % :param mdot:
        %     Mass flow rate
        %
            calllib(ct, 'bdry_setMdot', d.domainID, mdot);
        end

        function setMoleFractions(d, x)
            % SETMOLEFRACTIONS  Set the mole fractions.
            % d.setMoleFractions(x)
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param x:
            %     String specifying the species and mole fractions in
            %     the format ``'SPEC:X,SPEC2:X2'``.
            %
            calllib(ct, 'bdry_setMoleFractions', d.domainID, x);
        end

        function setProfileD(d, n, p)
            % SETPROFILED  Set the profile of a component.
            % d.setProfileD(n, p)
            % Convenience function to allow an instance of :mat:func:`Domain1D` to
            % have a profile of its components set when it is part of a :mat:func:`Stack`.
            %
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param n:
            %     Integer index of component, vector of component indices, string
            %     of component name, or cell array of strings of component names.
            % :param p:
            %     n x 2 array, whose columns are the relative (normalized) positions
            %     and the component values at those points. The number of positions
            %     ``n`` is arbitrary.
            %
            if d.stack == 0
                error('Install domain in stack before calling setProfile.');
            end
            d.stack.setProfile(d.domainIndex, n, p);
        end

        function setSteadyTolerances(d, component, rtol, atol)
            % SETSTEADYTOLERANCES  Set the steady-state tolerances.
            % d.setSteadyTolerances(component, rtol, atol)
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param component:
            %     String or cell array of strings of component values
            %     whose tolerances should be set. If ``'default'`` is
            %     specified, the tolerance of all components will be set.
            % :param rtol:
            %     Relative tolerance
            % :param atol:
            %     Absolute tolerance
            %
            if strcmp(component, 'default')
                nc = d.nComponents;
                for ii = 1:nc
                    calllib(ct, 'domain_setSteadyTolerances', ...
                            d.domainID, ii, rtol, atol);
                end
            elseif iscell(component)
                nc = length(component);
                for ii = 1:nc
                    n = d.componentIndex(component{ii});
                    calllib(ct, 'domain_setSteadyTolerances', ...
                            d.domainID, n, rtol, atol);
                end
            else
                n = d.componentIndex(component);
                calllib(ct, 'domain_setSteadyTolerances', ...
                        d.domainID, ii, rtol, atol);
            end
        end

        function setTransientTolerances(d, component, rtol, atol)
            % SETTRANSIENTTOLERANCES  Set the transient tolerances.
            % d.setTransientTolerances(component, rtol, atol)
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param component:
            %     String or cell array of strings of component values
            %     whose tolerances should be set. If ``'default'`` is
            %     specified, the tolerance of all components will be set.
            % :param rtol:
            %     Relative tolerance
            % :param atol:
            %     Absolute tolerance
            %
            if strcmp(component, 'default')
                nc = d.nComponents;
                for ii = 1:nc
                    calllib(ct, 'domain_setTransientTolerances', ...
                            d.domainID, ii, rtol, atol);
                end
            elseif iscell(component)
                nc = length(component);
                for ii = 1:nc
                    n = d.componentIndex(component{ii});
                    calllib(ct, 'domain_setTransientTolerances', ...
                            d.domainID, n, rtol, atol);
                end
            else
                n = d.componentIndex(component);
                calllib(ct, 'domain_setTransientTolerances', ...
                        d.domainID, ii, rtol, atol);
            end
        end

        function setTransport(d, itr)
            % SETTRANSPORT  Set the solution object used for calculating transport properties.
            % d.setTransport(itr)
            % :param itr:
            %    ID of the solution object for which transport properties
            %    are calculated.
            %
            calllib(ct, 'stflow_setTransport', d.domainID, itr);
        end

        function setupGrid(d, grid)
            % SETUPGRID  Set up the solution grid.
            % d.setupGrid(grid)
            % :param d:
            %     Instance of class :mat:func:`Domain1D`
            % :param grid:
            %
            calllib(ct, 'domain_setupGrid', d.domainID, numel(grid), grid);
        end

    end
end