table 72101 "DOPSWHS Service Technician"
{
    DataClassification = CustomerContent;
    fields
    {
        field(1; "User Name"; Code[50]) { TableRelation = User."User Name"; ValidateTableRelation = false; }
        field(2; "Resource No."; Code[20])
        {
            TableRelation = Resource where(Type = const(Person));
            NotBlank = true;
            trigger OnValidate()
            begin
                CheckResource();
            end;
        }
        field(3; "Resource Name"; Text[100])
        {
            FieldClass = FlowField;
            CalcFormula = lookup(Resource.Name where("No." = field("Resource No.")));
            Editable = false;
        }
        field(4; "Van Location Code"; Code[10]) { TableRelation = Location; }
        field(5; Dispatcher; Boolean) { }
        field(6; Active; Boolean)
        {
            InitValue = true;
            trigger OnValidate()
            begin
                if "Resource No." <> '' then
                    CheckResource();
            end;
        }
    }
    keys { key(PK; "User Name") { Clustered = true; } }
    trigger OnInsert()
    begin
        CheckResource();
    end;
    trigger OnModify()
    begin
        CheckResource();
    end;
    local procedure CheckResource()
    var
        Tech: Record "DOPSWHS Service Technician";
        Res: Record Resource;
    begin
        TestField("Resource No.");
        Res.Get("Resource No.");
        Res.TestField(Type, Res.Type::Person);
        if not Active then
            exit;
        Tech.LockTable();
        Tech.SetRange("Resource No.", "Resource No.");
        Tech.SetRange(Active, true);
        Tech.SetFilter("User Name", '<>%1', "User Name");
        if not Tech.IsEmpty() then
            Error(DuplicateResourceErr, "Resource No.");
    end;
    var
        DuplicateResourceErr: Label 'Kaynak %1 başka bir aktif teknisyene bağlı.', Comment = '%1 = Kaynak numarası';
}
