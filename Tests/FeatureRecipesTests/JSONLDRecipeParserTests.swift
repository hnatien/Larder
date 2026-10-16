import LarderCore
import Testing
@testable import FeatureRecipes

struct JSONLDRecipeParserTests {
    @Test func parsesTopLevelObject() throws {
        let parsed = try JSONLDRecipeParser.parseStructured(html: Fixture.html("object"))
        let recipe = parsed.recipe
        #expect(recipe.title == "Weeknight chana masala & rice")
        #expect(recipe.servings == 4)
        #expect(recipe.prepMinutes == 10)
        #expect(recipe.cookMinutes == 25)
        #expect(recipe.ingredients.count == 5)
        #expect(recipe.steps.count == 2)
        #expect(parsed.tags.cuisine == "Indian")
        #expect(parsed.tags.mealTypes == [.dinner])
    }

    @Test func parsesIngredientLinesOfObject() throws {
        let recipe = try JSONLDRecipeParser.parse(html: Fixture.html("object"))
        let rice = recipe.ingredients[1]
        #expect(rice.quantity == 1.5)
        #expect(rice.unit == .cup)
        #expect(rice.name == "basmati rice")
        let chickpeas = recipe.ingredients[3]
        #expect(chickpeas.quantity == 400)
        #expect(chickpeas.unit == .gram)
        #expect(chickpeas.name == "chickpeas, drained")
        #expect(chickpeas.rawText == "1 (400 g) can chickpeas, drained")
        #expect(recipe.ingredients[4].quantity == nil)
    }

    @Test func readsAPhotoAddressString() throws {
        let parsed = try JSONLDRecipeParser.parseStructured(html: Fixture.html("object"))
        #expect(parsed.imageAddress == "https://example.com/photo.jpg")
    }

    @Test func readsThePhotoAddressOfAnImageObjectOrArray() throws {
        let forms: [(json: String, expected: String?)] = [
            (#"{"@type":"ImageObject","url":"https://example.com/a.jpg"}"#, "https://example.com/a.jpg"),
            (#"{"@type":"ImageObject","contentUrl":"https://example.com/b.jpg"}"#, "https://example.com/b.jpg"),
            (#"["https://example.com/c-16x9.jpg","https://example.com/c-1x1.jpg"]"#, "https://example.com/c-16x9.jpg"),
            (#"[{"@type":"ImageObject"},{"@type":"ImageObject","url":"/d.jpg"}]"#, "/d.jpg"),
            (#"" ""#, nil),
            (#"[]"#, nil),
            (#"42"#, nil),
        ]
        for form in forms {
            let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"Toast","recipeIngredient":["bread"],"image":"# + form.json + "}")
            #expect(try JSONLDRecipeParser.parseStructured(html: html).imageAddress == form.expected, "\(form.json)")
        }
    }

    @Test func followsAnImageReferenceIntoTheGraph() throws {
        let html = Sample.html(recipeJSON: #"""
            {"@context":"https://schema.org","@graph":[
              {"@type":"ImageObject","@id":"https://example.com/#primaryimage","url":"https://example.com/hero.jpg"},
              {"@type":"Recipe","name":"Toast","recipeIngredient":["bread"],"image":{"@id":"https://example.com/#primaryimage"}}
            ]}
            """#)
        #expect(try JSONLDRecipeParser.parseStructured(html: html).imageAddress == "https://example.com/hero.jpg")
    }

    @Test func anImageReferenceThatPointsNowhereGivesNoPhotoAddress() throws {
        let html = Sample.html(recipeJSON: #"""
            {"@graph":[
              {"@type":"ImageObject","@id":"#a","image":{"@id":"#a"}},
              {"@type":"Recipe","name":"Toast","recipeIngredient":["bread"],"image":[{"@id":"#missing"},{"@id":"#a"}]}
            ]}
            """#)
        #expect(try JSONLDRecipeParser.parseStructured(html: html).imageAddress == nil)
    }

    @Test func aRecipeWithoutAnImageHasNoPhotoAddress() throws {
        #expect(try JSONLDRecipeParser.parseStructured(html: Fixture.html("graph")).imageAddress == nil)
    }

    @Test func detectsTimersInSteps() throws {
        let recipe = try JSONLDRecipeParser.parse(html: Fixture.html("object"))
        #expect(recipe.steps[0].timerSeconds == nil)
        #expect(recipe.steps[1].timerSeconds == 600)
    }

    @Test func parsesTopLevelArrayWithTypeArrayAndStringInstructions() throws {
        let parsed = try JSONLDRecipeParser.parseStructured(html: Fixture.html("array"))
        #expect(parsed.recipe.title == "Oat porridge")
        #expect(parsed.recipe.servings == 2)
        #expect(parsed.recipe.prepMinutes == 0)
        #expect(parsed.recipe.cookMinutes == 10)
        #expect(parsed.recipe.steps.map(\.text) == ["Combine the oats and milk.", "Simmer for 8 minutes, stirring."])
        #expect(parsed.recipe.steps[1].timerSeconds == 480)
        #expect(parsed.tags.mealTypes == [.breakfast])
        #expect(parsed.recipe.ingredients[2].unit == .pinch)
    }

    @Test func parsesGraphAfterAnUnrelatedBlock() throws {
        let parsed = try JSONLDRecipeParser.parseStructured(html: Fixture.html("graph"))
        #expect(parsed.recipe.title == "Tomato soup")
        #expect(parsed.recipe.servings == 6)
        #expect(parsed.recipe.prepMinutes == 15)
        #expect(parsed.recipe.cookMinutes == 80)
        #expect(parsed.tags.cuisine == "Italian")
        #expect(parsed.recipe.ingredients[2].name == "Fresh basil")
        #expect(parsed.recipe.steps[0].timerSeconds == 2700)
    }

    @Test func flattensHowToSections() throws {
        let recipe = try JSONLDRecipeParser.parse(html: Fixture.html("section"))
        #expect(recipe.servings == 8)
        #expect(recipe.steps.map(\.text) == [
            "Brown the mince.",
            "Add the tomatoes and simmer for 30 minutes.",
            "Layer the sheets and sauce.",
            "Bake for 1 hour 15 minutes.",
        ])
        #expect(recipe.steps[1].timerSeconds == 1800)
        #expect(recipe.steps[3].timerSeconds == 4500)
    }

    @Test func missingOptionalFieldsStayNil() throws {
        let parsed = try JSONLDRecipeParser.parseStructured(html: Fixture.html("minimal"))
        #expect(parsed.recipe.servings == nil)
        #expect(parsed.recipe.prepMinutes == nil)
        #expect(parsed.recipe.cookMinutes == nil)
        #expect(parsed.tags == RecipeTags())
        #expect(parsed.recipe.ingredients.count == 1)
    }

    @Test func pageWithoutRecipeThrows() throws {
        let html = try Fixture.html("no-recipe")
        #expect(throws: JSONLDRecipeParser.ParseError.noRecipe) { try JSONLDRecipeParser.parse(html: html) }
    }

    @Test func recipeWithoutIngredientsOrStepsThrows() throws {
        let html = try Fixture.html("empty-recipe")
        #expect(throws: JSONLDRecipeParser.ParseError.noRecipe) { try JSONLDRecipeParser.parse(html: html) }
    }

    @Test func pageWithoutAnyScriptThrows() {
        #expect(throws: JSONLDRecipeParser.ParseError.noRecipe) { try JSONLDRecipeParser.parse(html: "<html><body>Hello</body></html>") }
        #expect(throws: JSONLDRecipeParser.ParseError.noRecipe) { try JSONLDRecipeParser.parse(html: "") }
    }

    @Test func unterminatedScriptDoesNotCrash() {
        #expect(throws: JSONLDRecipeParser.ParseError.noRecipe) {
            try JSONLDRecipeParser.parse(html: "<script type=\"application/ld+json\">{\"@type\":\"Recipe\"")
        }
    }

    @Test func recipeWithoutTitleThrows() {
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","recipeIngredient":["1 egg"]}"#)
        #expect(throws: JSONLDRecipeParser.ParseError.noRecipe) { try JSONLDRecipeParser.parse(html: html) }
    }

    @Test func acceptsSchemaUrlTypes() throws {
        let html = Sample.html(recipeJSON: #"{"@type":"http://schema.org/Recipe","name":"Eggs","recipeIngredient":["2 eggs"]}"#)
        #expect(try JSONLDRecipeParser.parse(html: html).title == "Eggs")
    }

    @Test(arguments: [
        ("\"4 servings\"", 4), ("\"Serves 6\"", 6), ("12", 12), ("\"4-6\"", 6), ("[\"8\", \"8 servings\"]", 8),
    ])
    func yieldVariants(literal: String, expected: Int) throws {
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"X","recipeYield":\#(literal),"recipeIngredient":["1 egg"]}"#)
        #expect(try JSONLDRecipeParser.parse(html: html).servings == expected)
    }

    @Test(arguments: ["\"lots\"", "0", "5000", "null"])
    func unusableYieldIsNil(literal: String) throws {
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"X","recipeYield":\#(literal),"recipeIngredient":["1 egg"]}"#)
        #expect(try JSONLDRecipeParser.parse(html: html).servings == nil)
    }

    @Test func totalTimeAloneIsCookTime() throws {
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"X","totalTime":"PT45M","recipeIngredient":["1 egg"]}"#)
        let recipe = try JSONLDRecipeParser.parse(html: html)
        #expect(recipe.prepMinutes == 0)
        #expect(recipe.cookMinutes == 45)
    }

    @Test func totalTimeFillsTheMissingHalf() throws {
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"X","prepTime":"PT10M","totalTime":"PT45M","recipeIngredient":["1 egg"]}"#)
        let recipe = try JSONLDRecipeParser.parse(html: html)
        #expect(recipe.prepMinutes == 10)
        #expect(recipe.cookMinutes == 35)
    }

    @Test func stripsMarkupFromInstructions() throws {
        let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"X","recipeInstructions":["Stir <b>well</b> &amp; serve."]}"#)
        #expect(try JSONLDRecipeParser.parse(html: html).steps.map(\.text) == ["Stir well & serve."])
    }

    @Test func mealTypeHeuristics() throws {
        let cases: [(String, Set<MealType>)] = [
            ("Main Course", [.dinner]), ("Lunch", [.lunch]), ("Brunch", [.breakfast]),
            ("Appetizer", [.snack]), ("Dessert", []),
        ]
        for (category, expected) in cases {
            let html = Sample.html(recipeJSON: #"{"@type":"Recipe","name":"X","recipeCategory":"\#(category)","recipeIngredient":["1 egg"]}"#)
            #expect(try JSONLDRecipeParser.parseStructured(html: html).tags.mealTypes == expected, "\(category)")
        }
    }
}
