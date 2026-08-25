import Foundation

/// Lizenztexte für die Anzeige in der App. Die englische MIT-Fassung ist die
/// verbindliche Lizenz; die deutsche Fassung dient der Verständlichkeit.
enum AppLicense {
    static func mitText(for language: Localization.Lang) -> String {
        switch language {
        case .de:
            return """
            MIT-Lizenz

            Copyright (c) 2026 Norbert Jander

            Hiermit wird jeder Person, die eine Kopie dieser Software und der zugehörigen Dokumentationsdateien (die „Software“) erhält, unentgeltlich die Erlaubnis erteilt, uneingeschränkt mit der Software zu handeln, einschließlich und ohne Einschränkung des Rechts, die Software zu nutzen, zu kopieren, zu verändern, zusammenzuführen, zu veröffentlichen, zu verbreiten, Unterlizenzen zu vergeben und/oder Kopien der Software zu verkaufen sowie Personen, denen die Software überlassen wird, dies unter den folgenden Bedingungen zu gestatten:

            Der obige Urheberrechtshinweis und dieser Erlaubnishinweis müssen in allen Kopien oder wesentlichen Teilen der Software enthalten sein.

            DIE SOFTWARE WIRD OHNE JEGLICHE AUSDRÜCKLICHE ODER STILLSCHWEIGENDE GEWÄHRLEISTUNG BEREITGESTELLT, EINSCHLIESSLICH, ABER NICHT BESCHRÄNKT AUF DIE GEWÄHRLEISTUNG DER MARKTGÄNGIGKEIT, DER EIGNUNG FÜR EINEN BESTIMMTEN ZWECK UND DER NICHTVERLETZUNG VON RECHTEN. IN KEINEM FALL SIND DIE AUTOREN ODER URHEBERRECHTSINHABER FÜR ANSPRÜCHE, SCHÄDEN ODER SONSTIGE HAFTUNG VERANTWORTLICH, OB AUS EINEM VERTRAG, EINER UNERLAUBTEN HANDLUNG ODER ANDERWEITIG, DIE SICH AUS ODER IN VERBINDUNG MIT DER SOFTWARE ODER DER NUTZUNG ODER SONSTIGEN HANDHABUNG DER SOFTWARE ERGEBEN.

            Hinweis: Diese deutsche Übersetzung dient nur der Information. Verbindlich ist die englische Fassung der MIT-Lizenz.
            """
        case .en:
            return """
            MIT License

            Copyright (c) 2026 Norbert Jander

            Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
            """
        }
    }
}
