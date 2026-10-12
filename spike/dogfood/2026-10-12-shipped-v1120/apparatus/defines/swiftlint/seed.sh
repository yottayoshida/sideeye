set -eu
# A source file with violations `--fix` corrects (trailing semicolons, trailing whitespace,
# a missing space before a brace): SwiftLint rewrites it in place.
rm -rf /s/sw && mkdir -p /s/sw/Sources
cat > /s/sw/Sources/Ledger.swift <<'EOF'
import Foundation

/// A household ledger: entries in, a balance out.
struct Entry {
    let date: Date;
    let amount: Decimal;
    let memo: String;
}

final class Ledger{
    private(set) var entries: [Entry] = [];

    func add(_ amount: Decimal, memo: String) {
        entries.append(Entry(date: Date(), amount: amount, memo: memo));   
    }

    var balance: Decimal{
        entries.reduce(0) { $0 + $1.amount };
    }

    func largest(_ n: Int) -> [Entry] {
        Array(entries.sorted { $0.amount > $1.amount }.prefix(n));  
    }
}

let ledger = Ledger();
ledger.add(1200, memo: "salary");
ledger.add(-85.5, memo: "groceries");   
ledger.add(-40, memo: "phone");
print(ledger.balance);
EOF
