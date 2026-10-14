import Foundation

protocol FarmAreaRepository: AnyObject {
    var areas: [FarmArea] { get }
    func importFile(_ input: URL) throws
}
