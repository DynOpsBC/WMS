enum 50105 "WMS Wave Status"
{
    Extensible = true;
    value(0; Planned) { Caption = 'Planned'; }
    value(1; Released) { Caption = 'Released'; }
    value(2; "In Progress") { Caption = 'In Progress'; }
    value(3; Complete) { Caption = 'Complete'; }
}

enum 50106 "WMS Pick Grouping"
{
    Extensible = true;
    value(0; "User Grouped") { Caption = 'User Grouped'; }
    value(1; "System Grouped") { Caption = 'System Grouped'; }
    value(2; "Validated User Directed") { Caption = 'Validated User Directed'; }
    value(3; Cluster) { Caption = 'Cluster Pick'; }
}
