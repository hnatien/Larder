#!/usr/bin/env python3
"""Validate the Larder seed foods and recipes. Run: python3 -I Tools/validate-seed.py"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

SEED = Path(__file__).resolve().parent.parent / "App" / "Larder" / "Resources" / "Seed"

FOOD_GROUPS = {"produce", "grains", "protein", "dairy", "fats", "legumes", "other"}
SOURCES = {"fdcFoundation", "srLegacy", "fdcBranded", "offUnverified", "seedApproximate"}
ALLERGENS = {"milk", "egg", "fish", "crustacean", "mollusc", "treeNut", "peanut", "wheat", "gluten",
             "soy", "sesame", "celery", "mustard", "lupin", "sulphites"}
PRESENCE = {"contains", "mayContain", "unknown", "verifiedFree"}
TAGS = {"meat", "pork", "beef", "poultry", "fish", "shellfish", "egg", "dairy", "honey", "alcohol",
        "glutenGrain", "rawFish", "unpasteurised", "highSodium", "addedSugarSource"}
UNITS = {"gram", "kilogram", "milligram", "millilitre", "litre", "teaspoon", "tablespoon", "cup",
         "fluidOunce", "ounce", "pound", "piece", "pinch", "clove", "slice"}
MEAL_TYPES = {"breakfast", "lunch", "dinner", "snack"}
EQUIPMENT = {"oven", "stovetop", "microwave", "airFryer", "slowCooker", "pressureCooker", "blender",
             "foodProcessor", "grill"}
DIET_FLAGS = {"vegetarian", "vegan", "pescatarian", "mediterranean", "dash"}
NUTRIENTS = {"energyKcal", "proteinG", "fatG", "saturatedFatG", "monounsaturatedFatG",
             "polyunsaturatedFatG", "carbohydrateG", "fiberG", "totalSugarG", "addedSugarG",
             "sodiumMg", "potassiumMg", "calciumMg", "ironMg", "vitaminDMcg", "vitaminB12Mcg"}
FOOD_KEYS = {"slug", "name", "source", "foodGroup", "tags", "allergens", "portions", "densityGPerMl",
             "per100g"}
RECIPE_KEYS = {"slug", "title", "servings", "prepMinutes", "cookMinutes", "cuisine", "mealTypes",
               "equipment", "dietFlags", "ingredients", "steps"}
INGREDIENT_KEYS = {"text", "quantity", "unit", "food", "optional", "garnish"}
STEP_KEYS = {"text", "timerSeconds"}
ANIMAL_FOR_VEGAN = {"meat", "pork", "beef", "poultry", "fish", "shellfish", "egg", "dairy", "honey"}
FLESH = {"meat", "pork", "beef", "poultry", "fish", "shellfish"}
SEA = {"fish", "shellfish"}
MEAT = {"meat", "pork", "beef", "poultry"}
KEBAB = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
BANNED_WORDS = re.compile(r"\b(good|bad|clean|cheat)\b", re.IGNORECASE)

problems = []


def fail(slug, key, message):
    problems.append(f"{slug} {key}: {message}")


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def check_keys(slug, obj, allowed, where):
    if not isinstance(obj, dict):
        fail(slug, where, "expected an object")
        return False
    for k in sorted(set(obj) - allowed):
        fail(slug, f"{where}.{k}" if where else k, "unexpected key")
    for k in sorted(allowed - set(obj)):
        fail(slug, f"{where}.{k}" if where else k, "missing key")
    return True


def check_copy(slug, key, text):
    if not isinstance(text, str):
        fail(slug, key, "expected a string")
        return
    if "!" in text:
        fail(slug, key, "contains an exclamation mark")
    if "—" in text:
        fail(slug, key, "contains an em dash")
    m = BANNED_WORDS.search(text)
    if m:
        fail(slug, key, f"contains banned word '{m.group(0)}'")


def check_slug(slug, seen, kind):
    if not isinstance(slug, str) or not KEBAB.match(slug):
        fail(str(slug), "slug", "not kebab-case")
    if slug in seen:
        fail(str(slug), "slug", f"duplicate {kind} slug")
    seen.add(slug)


def check_food(food):
    slug = food.get("slug", "?")
    if not check_keys(slug, food, FOOD_KEYS, ""):
        return
    check_copy(slug, "name", food["name"])
    if food["source"] not in SOURCES:
        fail(slug, "source", f"invalid value {food['source']!r}")
    if food["foodGroup"] not in FOOD_GROUPS:
        fail(slug, "foodGroup", f"invalid value {food['foodGroup']!r}")
    if not isinstance(food["tags"], list) or any(t not in TAGS for t in food["tags"]):
        fail(slug, "tags", "must be a list of known tags")
    elif len(set(food["tags"])) != len(food["tags"]):
        fail(slug, "tags", "duplicate tags")
    if not isinstance(food["allergens"], dict):
        fail(slug, "allergens", "expected an object")
    else:
        for k, v in food["allergens"].items():
            if k not in ALLERGENS:
                fail(slug, f"allergens.{k}", "unknown allergen")
            if v not in PRESENCE:
                fail(slug, f"allergens.{k}", f"invalid value {v!r}")
    portions = food["portions"]
    if not isinstance(portions, list) or not portions:
        fail(slug, "portions", "needs at least one portion")
    else:
        for i, p in enumerate(portions):
            if not check_keys(slug, p, {"label", "grams"}, f"portions[{i}]"):
                continue
            check_copy(slug, f"portions[{i}].label", p["label"])
            if not is_number(p["grams"]) or not 0.5 <= p["grams"] <= 2000:
                fail(slug, f"portions[{i}].grams", "must be a number from 0.5 to 2000")
    d = food["densityGPerMl"]
    if d is not None and (not is_number(d) or not 0.1 <= d <= 3):
        fail(slug, "densityGPerMl", "must be null or a number from 0.1 to 3")
    per = food["per100g"]
    if not isinstance(per, dict):
        fail(slug, "per100g", "expected an object")
        return
    for k, v in per.items():
        if k not in NUTRIENTS:
            fail(slug, f"per100g.{k}", "unknown nutrient")
        elif not is_number(v) or v < 0:
            fail(slug, f"per100g.{k}", "must be a non-negative number")
    if any(k in per and not is_number(per[k]) for k in per):
        return
    kcal = per.get("energyKcal")
    if kcal is not None and not 0 <= kcal <= 900:
        fail(slug, "per100g.energyKcal", "outside 0-900")
    for k in ("proteinG", "fatG", "carbohydrateG"):
        if k in per and not 0 <= per[k] <= 100:
            fail(slug, f"per100g.{k}", "outside 0-100")
    p, fat, c, fib = (per.get(k, 0) for k in ("proteinG", "fatG", "carbohydrateG", "fiberG"))
    if p + fat + c > 105:
        fail(slug, "per100g", f"protein+fat+carbohydrate is {p + fat + c:.1f} g, above 105")
    if kcal is not None and all(k in per for k in ("proteinG", "fatG", "carbohydrateG")):
        plain = 4 * p + 9 * fat + 4 * c
        adjusted = 4 * p + 9 * fat + 4 * max(c - fib, 0) + 2 * fib
        if not any(abs(kcal - e) <= max(0.15 * e, 12 if e <= 60 else 0) for e in (plain, adjusted)):
            fail(slug, "per100g.energyKcal",
                 f"{kcal} is not within 15% of 4p+9f+4c = {plain:.0f} (fibre-adjusted {adjusted:.0f})")
    for k, v in per.items():
        if k in ("saturatedFatG", "monounsaturatedFatG", "polyunsaturatedFatG") and "fatG" in per and v > per["fatG"] + 0.01:
            fail(slug, f"per100g.{k}", "exceeds total fat")
        if k in ("totalSugarG", "addedSugarG", "fiberG") and "carbohydrateG" in per and v > per["carbohydrateG"] + 0.01:
            fail(slug, f"per100g.{k}", "exceeds total carbohydrate")


def check_ingredient(slug, i, ing, foods):
    where = f"ingredients[{i}]"
    if not check_keys(slug, ing, INGREDIENT_KEYS, where):
        return
    check_copy(slug, f"{where}.text", ing["text"])
    if not is_number(ing["quantity"]) or ing["quantity"] <= 0:
        fail(slug, f"{where}.quantity", "must be a positive number")
    if ing["unit"] not in UNITS:
        fail(slug, f"{where}.unit", f"invalid value {ing['unit']!r}")
    if ing["food"] not in foods:
        fail(slug, f"{where}.food", f"unknown food slug {ing['food']!r}")
    for k in ("optional", "garnish"):
        if not isinstance(ing[k], bool):
            fail(slug, f"{where}.{k}", "must be a boolean")


def check_step(slug, i, step):
    where = f"steps[{i}]"
    if not check_keys(slug, step, STEP_KEYS, where):
        return
    check_copy(slug, f"{where}.text", step["text"])
    words = len(step["text"].split())
    if not 8 <= words <= 20:
        fail(slug, f"{where}.text", f"{words} words, expected 8-20")
    t = step["timerSeconds"]
    if t is not None and (isinstance(t, bool) or not isinstance(t, int) or not 1 <= t <= 86400):
        fail(slug, f"{where}.timerSeconds", "must be null or an integer from 1 to 86400")


def check_diet(slug, recipe, foods):
    tags = set()
    for ing in recipe["ingredients"]:
        food = foods.get(ing.get("food"))
        if food:
            tags |= set(food["tags"])
    flags = set(recipe["dietFlags"])
    if "vegan" in flags and tags & ANIMAL_FOR_VEGAN:
        fail(slug, "dietFlags", f"vegan but ingredients carry {sorted(tags & ANIMAL_FOR_VEGAN)}")
    if "vegetarian" in flags and tags & FLESH:
        fail(slug, "dietFlags", f"vegetarian but ingredients carry {sorted(tags & FLESH)}")
    if "pescatarian" in flags:
        if tags & MEAT:
            fail(slug, "dietFlags", f"pescatarian but ingredients carry {sorted(tags & MEAT)}")
        if not tags & SEA:
            fail(slug, "dietFlags", "pescatarian but no fish or shellfish ingredient")


def check_recipe(recipe, foods):
    slug = recipe.get("slug", "?")
    if not check_keys(slug, recipe, RECIPE_KEYS, ""):
        return
    check_copy(slug, "title", recipe["title"])
    check_copy(slug, "cuisine", recipe["cuisine"])
    if isinstance(recipe["servings"], bool) or not isinstance(recipe["servings"], int) or not 1 <= recipe["servings"] <= 12:
        fail(slug, "servings", "must be an integer from 1 to 12")
    for k in ("prepMinutes", "cookMinutes"):
        v = recipe[k]
        if isinstance(v, bool) or not isinstance(v, int) or not 0 <= v <= 180:
            fail(slug, k, "must be an integer from 0 to 180")
    if all(isinstance(recipe[k], int) for k in ("prepMinutes", "cookMinutes")):
        total = recipe["prepMinutes"] + recipe["cookMinutes"]
        if not 10 <= total <= 45:
            fail(slug, "prepMinutes+cookMinutes", f"total {total} minutes, expected 10-45")
    for key, allowed in (("mealTypes", MEAL_TYPES), ("equipment", EQUIPMENT), ("dietFlags", DIET_FLAGS)):
        v = recipe[key]
        if not isinstance(v, list) or any(x not in allowed for x in v):
            fail(slug, key, "must be a list of known values")
        elif len(set(v)) != len(v):
            fail(slug, key, "duplicate values")
    if not recipe["mealTypes"]:
        fail(slug, "mealTypes", "needs at least one value")
    ingredients, steps = recipe["ingredients"], recipe["steps"]
    if not isinstance(ingredients, list) or not 3 <= len(ingredients) <= 10:
        fail(slug, "ingredients", "needs 3-10 ingredients")
    else:
        for i, ing in enumerate(ingredients):
            check_ingredient(slug, i, ing, foods)
        if all(i.get("optional") or i.get("garnish") for i in ingredients if isinstance(i, dict)):
            fail(slug, "ingredients", "every ingredient is optional or garnish")
    if not isinstance(steps, list) or not steps:
        fail(slug, "steps", "needs at least one step")
    else:
        for i, step in enumerate(steps):
            check_step(slug, i, step)
    if isinstance(ingredients, list) and isinstance(recipe["dietFlags"], list):
        check_diet(slug, recipe, foods)


def load(name, root_key):
    try:
        data = json.loads((SEED / name).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        fail(name, "file", str(e))
        return []
    if not isinstance(data, dict) or set(data) != {root_key} or not isinstance(data[root_key], list):
        fail(name, "root", f"expected an object with only the key '{root_key}' holding a list")
        return []
    return data[root_key]


def main():
    foods_list = load("seed-foods.json", "foods")
    recipes_list = load("seed-recipes.json", "recipes")
    seen = set()
    foods = {}
    for food in foods_list:
        if isinstance(food, dict):
            check_slug(food.get("slug"), seen, "food")
            check_food(food)
            foods[food.get("slug")] = food
        else:
            fail("seed-foods.json", "foods", "entry is not an object")
    seen = set()
    for recipe in recipes_list:
        if isinstance(recipe, dict):
            check_slug(recipe.get("slug"), seen, "recipe")
            check_recipe(recipe, foods)
        else:
            fail("seed-recipes.json", "recipes", "entry is not an object")

    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} problem(s)")
        sys.exit(1)

    valid = [r for r in recipes_list]
    print(f"foods: {len(foods_list)}  recipes: {len(valid)}")
    print("meal types:", dict(sorted(Counter(m for r in valid for m in r["mealTypes"]).items())))
    cuisines = Counter(r["cuisine"] for r in valid)
    print(f"cuisines ({len(cuisines)}):", dict(sorted(cuisines.items())))
    print("diet flags:", dict(sorted(Counter(f for r in valid for f in r["dietFlags"]).items())))
    leftovers = sum(1 for r in valid if "keeps for 3 days" in r["steps"][-1]["text"])
    timers = sum(1 for r in valid for s in r["steps"] if s["timerSeconds"] is not None)
    print(f"leftover-friendly recipes: {leftovers}  timed steps: {timers}")
    used = {i["food"] for r in valid for i in r["ingredients"]}
    unused = sorted(set(foods) - used)
    print(f"foods never used by a recipe ({len(unused)}):", ", ".join(unused) if unused else "none")


if __name__ == "__main__":
    main()
