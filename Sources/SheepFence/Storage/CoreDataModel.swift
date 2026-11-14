import CoreData

enum CoreDataModel {
    static func make() -> NSManagedObjectModel {
        let dataset = NSEntityDescription()
        dataset.name = "DatasetRecord"
        dataset.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let region = NSEntityDescription()
        region.name = "RegionRecord"
        region.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let datasetID = attribute("datasetID", type: .stringAttributeType)
        let revision = attribute("revision", type: .integer64AttributeType)
        let generatedAt = attribute("generatedAt", type: .dateAttributeType)
        let sourceBytes = attribute("sourceBytes", type: .binaryDataAttributeType)
        let sha256 = attribute("sha256", type: .binaryDataAttributeType)

        let featureID = attribute("featureID", type: .stringAttributeType)
        let name = attribute("name", type: .stringAttributeType)
        let enabled = attribute("enabled", type: .booleanAttributeType)
        let priority = attribute("priority", type: .integer64AttributeType)
        let ordinal = attribute("ordinal", type: .integer64AttributeType)
        let geometry = attribute("geometry", type: .binaryDataAttributeType)
        let bounds = attribute("bounds", type: .binaryDataAttributeType)

        let regions = NSRelationshipDescription()
        regions.name = "regions"
        regions.destinationEntity = region
        regions.deleteRule = .cascadeDeleteRule
        regions.isOptional = true
        regions.maxCount = 0

        let owner = NSRelationshipDescription()
        owner.name = "dataset"
        owner.destinationEntity = dataset
        owner.deleteRule = .nullifyDeleteRule
        owner.isOptional = false
        owner.minCount = 1
        owner.maxCount = 1
        regions.inverseRelationship = owner
        owner.inverseRelationship = regions

        dataset.properties = [datasetID, revision, generatedAt, sourceBytes, sha256, regions]
        dataset.uniquenessConstraints = [["datasetID"]]
        region.properties = [featureID, name, enabled, priority, ordinal, geometry, bounds, owner]

        let model = NSManagedObjectModel()
        model.entities = [dataset, region]
        return model
    }

    private static func attribute(_ name: String, type: NSAttributeType) -> NSAttributeDescription {
        let result = NSAttributeDescription()
        result.name = name
        result.attributeType = type
        result.isOptional = false
        return result
    }
}
