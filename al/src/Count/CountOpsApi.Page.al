page 72232 "DOPSWHS Count Ops API"
{
    // Hosts count operations that do not belong to an existing sheet.  The
    // singleton Setup record gives mobile a stable key:
    //   POST countOps('')/Microsoft.NAV.createV2
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'countOp';
    EntitySetName = 'countOps';
    SourceTable = "DOPSWHS Setup";
    ODataKeyFields = "Primary Key";
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(primaryKey; Rec."Primary Key") { Caption = 'primaryKey'; Editable = false; }
            }
        }
    }

    [ServiceEnabled]
    procedure createV2(locationCode: Code[10]; userId: Code[50]): Code[20]
    var
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        exit(CountMgmt.CreateV2Sheet(locationCode, userId));
    end;

    [ServiceEnabled]
    procedure createV2Filtered(locationCode: Code[10]; zoneCode: Code[10]; userId: Code[50]): Code[20]
    var
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        exit(CountMgmt.CreateV2SheetFiltered(locationCode, zoneCode, userId));
    end;

    /// <summary>
    /// Klasik (satır üretimli) sayım sayfası açar. Terminalde yeni klasik sayfa
    /// oluşturmanın hiçbir yolu yoktu; ofisin BC'de sayfa açmasını beklemek
    /// gerekiyordu (UAT count-26). Sayıcılar boş bırakılabilir.
    /// </summary>
    [ServiceEnabled]
    procedure createClassic(locationCode: Code[10]; counter1UserId: Code[50]; counter2UserId: Code[50]; counter3UserId: Code[50]): Code[20]
    var
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        Counters: array[3] of Code[50];
    begin
        Counters[1] := counter1UserId;
        Counters[2] := counter2UserId;
        Counters[3] := counter3UserId;
        RemoveUnavailableCounters(Counters);
        exit(CountMgmt.CreateSheet(locationCode, Enum::"DOPSWHS Count Mode"::Blind, Counters));
    end;

    [ServiceEnabled]
    procedure createClassicFiltered(locationCode: Code[10]; zoneCode: Code[10]; counter1UserId: Code[50]; counter2UserId: Code[50]; counter3UserId: Code[50]): Code[20]
    var
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
        CountHeader: Record "DOPSWHS Count Sheet Header";
        Counters: array[3] of Code[50];
        SheetNo: Code[20];
    begin
        Counters[1] := counter1UserId;
        Counters[2] := counter2UserId;
        Counters[3] := counter3UserId;
        RemoveUnavailableCounters(Counters);
        SheetNo := CountMgmt.CreateSheet(locationCode, Enum::"DOPSWHS Count Mode"::Blind, Counters);
        if zoneCode <> '' then begin
            CountHeader.Get(SheetNo);
            CountHeader.Validate("Zone Filter", zoneCode);
            CountHeader.Modify(true);
        end;
        exit(SheetNo);
    end;

    local procedure RemoveUnavailableCounters(var Counters: array[3] of Code[50])
    var
        LocalUser: Record "DOPSWHS Local User";
        Slot: Integer;
    begin
        for Slot := 1 to 3 do
            if Counters[Slot] <> '' then begin
                LocalUser.Reset();
                if not LocalUser.Get(CopyStr(Counters[Slot], 1, MaxStrLen(LocalUser.Username))) then
                    Counters[Slot] := ''
                else
                    if LocalUser.Disabled then
                        Counters[Slot] := '';
            end;
    end;
}
