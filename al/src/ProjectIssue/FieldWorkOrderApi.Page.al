page 72475 "DOPSWHS Field WO API"
{
    // Kitoko/Element4 #3338: terminal "Projeye Çıkış".
    //   GET  fieldWorkOrders                     → açık saha iş emirleri
    //   POST fieldWorkOrders('SIE-…')/Microsoft.NAV.issueItem {itemNo, …}
    // Kaynak geçici buffer'dır; Saha İş Emri (Proje Yönetimi uzantısı) RecordRef ile okunur.
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'fieldWorkOrder';
    EntitySetName = 'fieldWorkOrders';
    SourceTable = "DOPSWHS Field WO Buffer";
    SourceTableTemporary = true;
    ODataKeyFields = "No.";
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(projectNo; Rec."Project No.") { Caption = 'projectNo'; }
                field(projectTaskNo; Rec."Project Task No.") { Caption = 'projectTaskNo'; }
                field(projectDescription; Rec."Project Description") { Caption = 'projectDescription'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(team; Rec.Team) { Caption = 'team'; }
                field(plannedStart; Rec."Planned Start") { Caption = 'plannedStart'; }
                field(plannedFinish; Rec."Planned Finish") { Caption = 'plannedFinish'; }
                field(status; Rec.Status) { Caption = 'status'; }
                field(itemLineCount; Rec."Item Line Count") { Caption = 'itemLineCount'; }
            }
        }
    }

    trigger OnOpenPage()
    var
        ProjectIssueMgmt: Codeunit "DOPSWHS Project Issue Mgmt";
    begin
        ProjectIssueMgmt.FillOpenWorkOrders(Rec);
    end;

    [ServiceEnabled]
    procedure issueItem(itemNo: Code[20]; variantCode: Code[10]; quantity: Decimal; unitOfMeasureCode: Code[10]; locationCode: Code[10]; binCode: Code[20]; lpNo: Code[20]; lotNo: Code[50]; serialNo: Code[50]; userId: Code[50]): Text
    var
        ProjectIssueMgmt: Codeunit "DOPSWHS Project Issue Mgmt";
    begin
        exit(ProjectIssueMgmt.IssueItem(Rec."No.", itemNo, variantCode, quantity, unitOfMeasureCode, locationCode, binCode, lpNo, lotNo, serialNo, userId));
    end;
}
