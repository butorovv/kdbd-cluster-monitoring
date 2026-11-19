:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- initialization(main, main).

main :-
    source_file(main, Source),
    file_directory_name(Source, Dir),
    directory_file_path(Dir, 'scenarios.json', File),
    setup_call_cleanup(open(File, read, Stream),
                       json_read_dict(Stream, Data, [value_string_as(atom)]),
                       close(Stream)),
    run(Data, Result),
    json_write_dict(current_output, Result),
    nl.

group_path(Code, Groups, [Code]) :-
    member(Group, Groups),
    Group.code == Code,
    Group.kind == cluster,
    Group.parent == null.
group_path(Code, Groups, Path) :-
    member(Group, Groups),
    Group.code == Code,
    Group.kind == topological,
    group_path(Group.parent, Groups, Parents),
    append(Parents, [Code], Path).

count_kind(Kind, Components, Count) :-
    include(==(Kind), Components, Matching),
    length(Matching, Count).

reading(Scenario, Source, Value) :-
    findall(V, (member(Row, Scenario.samples), Row.source == Source, V = Row.value), [Value]).

diagnose(Data, Scenario, Source, _{status:unknown_source, reason:Reason}) :-
    \+ memberchk(Source, Scenario.sources),
    Reason = Data.knowledge.source_registration.
diagnose(Data, Scenario, Source, _{status:missing_sample, reason:Reason, action:Action}) :-
    memberchk(Source, Scenario.sources),
    \+ reading(Scenario, Source, _),
    Reason = Data.knowledge.missing,
    Action = Data.knowledge.check_source.
diagnose(Data, Scenario, Source, _{status:Status, reason:Reason}) :-
    memberchk(Source, Scenario.sources),
    reading(Scenario, Source, Value),
    Reason = Data.knowledge.limit,
    (Value >= Data.threshold -> Status = threshold_reached ; Status = below_threshold).

scenario_result(Data, Scenario, ID-Result) :-
    ID = Scenario.id,
    diagnose(Data, Scenario, 0, Result).

run(Data, Result) :-
    group_path(Data.node_group, Data.groups, Groups),
    append(Groups, [Data.node], Topology),
    count_kind(cpu, Data.components, CPU),
    count_kind(gpu, Data.components, GPU),
    count_kind(psu, Data.components, PSU),
    length(Data.components, Total),
    Total is CPU + GPU + PSU,
    Metric = Data.metric,
    Metric.kind == gpu,
    Metric.code == 'GPU_CORE_TEMP',
    Metric.unit == degC,
    member(Stock, Data.scenarios),
    Stock.id == stock,
    diagnose(Data, Stock, 5, Missing),
    maplist(scenario_result(Data), Data.scenarios, Pairs),
    dict_create(Diagnoses, diagnoses, Pairs),
    K = Data.knowledge,
    TopologyBasis = [K.node_membership, K.root_without_parent, K.topological_parent],
    ComponentsBasis = [K.component_kinds],
    TelemetryBasis = [K.gpu_temperature, K.source_registration, K.sample_uniqueness],
    Basis = _{topology:TopologyBasis, components:ComponentsBasis, telemetry:TelemetryBasis},
    Result = _{basis:Basis, topology:Topology, components: _{cpu:CPU, gpu:GPU, psu:PSU},
               missing_gpu5: Missing, diagnoses: Diagnoses}.
