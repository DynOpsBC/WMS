tableextension 72401 "DOPSWHS Bin Content Ext" extends "Bin Content"
{
    fields
    {
        field(72401; "DOPSWHS Root LP Count"; Integer)
        {
            Caption = 'Root LP Count';
            FieldClass = FlowField;
            CalcFormula = count("DOPSWHS LP Header" where("Bin Code" = field("Bin Code"), Status = const(Built), "Parent LP No." = const('')));
        }
    }
}
