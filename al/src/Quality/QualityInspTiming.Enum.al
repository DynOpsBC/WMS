enum 72001 "DOPSWHS Quality Insp. Timing"
{
    // Before Posting: the posting is refused until the inspection has a result.
    // After Posting: the posting creates the inspection itself and the received
    // lot stays on quality hold until it is passed.
    Extensible = true;
    Caption = 'Quality Inspection Timing';

    value(0; "Before Posting")
    {
        Caption = 'Before Posting';
    }
    value(1; "After Posting")
    {
        Caption = 'After Posting';
    }
}
