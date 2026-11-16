page 72100 "DOPSWHS Service Setup"
{
    PageType = Card;
    SourceTable = "DOPSWHS Service Setup";
    Caption = 'Service Terminal Setup';
    UsageCategory = Administration;
    ApplicationArea = All;
    InsertAllowed = false;
    DeleteAllowed = false;
    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';
                field(Enabled; Rec."Enabled") { ApplicationArea = All; Caption = 'Enabled';  }
                field(HideWarehouse; Rec."Hide Warehouse Modules") { ApplicationArea = All; Caption = 'Hide Warehouse Modules';  }
                field(WorkType; Rec."Default Work Type Code") { ApplicationArea = All; Caption = 'Default Work Type Code';  }
                field(Location; Rec."Default Location Code") { ApplicationArea = All; Caption = 'Default Location Code';  }
                field(Posting; Rec."Allow Terminal Posting") { ApplicationArea = All; Caption = 'Allow Terminal Posting';  }
                field(Signature; Rec."Require Signature") { ApplicationArea = All; Caption = 'Require Signature';  }
                field(Rounding; Rec."Labor Rounding (Hours)") { ApplicationArea = All; Caption = 'Labor Rounding (Hours)';  }
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(Technicians) { ApplicationArea = All; Caption = 'Service Technicians'; RunObject = page "DOPSWHS Service Technicians"; }
            action(Dispatch) { ApplicationArea = All; Caption = 'Service Management'; RunObject = page "DOPSWHS Service Dispatch"; }
            action(CreateDefaults)
            {
                ApplicationArea = All;
                Caption = 'Create Default Service Codes';
                Image = Setup;
                trigger OnAction()
                var
                    Defaults: Codeunit "DOPSWHS Service Defaults";
                begin
                    Defaults.CreateMissingDefaults();
                end;
            }
        }
    }
    trigger OnOpenPage()
    begin
        Rec.GetSetup();
    end;
}
