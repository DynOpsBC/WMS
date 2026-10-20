codeunit 72196 "DOPSWHS Prepared Label Tests"
{
    Subtype = Test;

    [Test]
    procedure SnapshotKeepsRepeatsBinsAndDescriptions()
    var
        Mgmt: Codeunit "DOPSWHS Prepared Label Mgmt";
        Row: Record "DOPSWHS Prepared Label Row";
        Count: Integer;
    begin
        Count := Mgmt.ReplaceList('TEST-PREP', DMY2Date(15, 10, 2026),
            '[{"order":1,"itemNo":"SAME","bin":"A2","description":"First"},{"order":2,"itemNo":"SAME","bin":"A1","description":"Second"}]');
        if Count <> 2 then
            Error('Each row must survive import.');
        Row.Get('TEST-PREP', 1);
        if (Row."Item No." <> 'SAME') or (Row."Bin Code" <> 'A2') or (Row.Description <> 'First') then
            Error('First row changed.');
        Row.Get('TEST-PREP', 2);
        if (Row."Item No." <> 'SAME') or (Row."Bin Code" <> 'A1') or (Row.Description <> 'Second') then
            Error('Repeated product or bin order lost.');
    end;

    [Test]
    procedure ReplacementDoesNotTouchAnotherList()
    var
        Mgmt: Codeunit "DOPSWHS Prepared Label Mgmt";
        Row: Record "DOPSWHS Prepared Label Row";
    begin
        Mgmt.ReplaceList('TEST-OTHER', Today(), '[{"order":1,"itemNo":"KEEP","bin":"B1"}]');
        Mgmt.ReplaceList('TEST-PREP', Today(), '[{"order":1,"itemNo":"OLD","bin":"A1"},{"order":2,"itemNo":"OLD","bin":"A2"}]');
        Mgmt.ReplaceList('TEST-PREP', Today(), '[{"order":1,"itemNo":"NEW","bin":"Z1"}]');
        Row.Get('TEST-OTHER', 1);
        if Row."Item No." <> 'KEEP' then
            Error('Another list changed.');
        Row.Get('TEST-PREP', 1);
        if Row."Item No." <> 'NEW' then
            Error('List was not replaced.');
        if Row.Get('TEST-PREP', 2) then
            Error('Old trailing row survived replacement.');
    end;

    [Test]
    procedure InvalidSequenceAndOverlongCodeAreRejected()
    var
        Mgmt: Codeunit "DOPSWHS Prepared Label Mgmt";
    begin
        asserterror Mgmt.ReplaceList('TEST-PREP', Today(), '[{"order":2,"itemNo":"X","bin":"A1"}]');
        if StrPos(GetLastErrorText(), 'kesintisiz') = 0 then
            Error('Expected a sequence error.');
        asserterror Mgmt.ReplaceList('TEST-PREP', Today(), '[{"order":1,"itemNo":"THIS-IS-OVER-TWENTY-CHARACTERS","bin":"A1"}]');
        if StrPos(GetLastErrorText(), 'geçersiz') = 0 then
            Error('Item numbers must never be silently truncated.');
    end;
}
