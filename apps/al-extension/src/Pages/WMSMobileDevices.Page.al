page 50029003 "WMS Mobile Devices"
{
    Caption = 'WMS Mobile Devices';
    PageType = List;
    SourceTable = "WMS Mobile Device";
    UsageCategory = Lists;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("Device ID"; Rec."Device ID") { ApplicationArea = All; }
                field("Device Name"; Rec."Device Name") { ApplicationArea = All; }
                field(Manufacturer; Rec.Manufacturer) { ApplicationArea = All; }
                field(Model; Rec.Model) { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; StyleExpr = StatusStyle; }
                field("Default Warehouse"; Rec."Default Warehouse") { ApplicationArea = All; }
                field("Paired At"; Rec."Paired At") { ApplicationArea = All; }
                field("Paired By"; Rec."Paired By") { ApplicationArea = All; }
                field("Last Seen"; Rec."Last Seen") { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Revoke)
            {
                Caption = 'Revoke';
                ApplicationArea = All;
                Image = Cancel;
                ToolTip = 'Revoke this device. The mobile app will be forced to re-pair.';

                trigger OnAction()
                var
                    Svc: Codeunit "WMS Pairing Svc";
                begin
                    if not Confirm('Revoke device %1?', false, Rec."Device ID") then exit;
                    Svc.RevokeDevice(Rec."Device ID", 'Admin revoked');
                    CurrPage.Update();
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        case Rec.Status of
            Rec.Status::Active: StatusStyle := 'Favorable';
            Rec.Status::Pending: StatusStyle := 'Attention';
            Rec.Status::Revoked: StatusStyle := 'Unfavorable';
            else
                StatusStyle := 'Standard';
        end;
    end;

    var
        StatusStyle: Text;
}
