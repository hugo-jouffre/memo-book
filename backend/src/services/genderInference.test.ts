import { describe, expect, it } from "vitest";
import { effectiveGender, inferGender } from "./genderInference.js";

describe("le genre deviné sur le prénom", () => {
  it("reconnaît les prénoms courants, accentués ou non", () => {
    expect(inferGender("Clara")).toBe("female");
    expect(inferGender("Élodie")).toBe("female");
    expect(inferGender("Elodie")).toBe("female");
    expect(inferGender("Hugo")).toBe("male");
    expect(inferGender("Jean-Pierre")).toBe("male");
  });

  it("ne lit que le premier prénom d'un composé à l'espace", () => {
    expect(inferGender("Marie Claire")).toBe("female");
    expect(inferGender("  paul  ")).toBe("male");
  });

  it("reste sans réponse devant un prénom mixte, inconnu ou absent", () => {
    expect(inferGender("Camille")).toBe("undisclosed");
    expect(inferGender("Dominique")).toBe("undisclosed");
    expect(inferGender("Xyzzy")).toBe("undisclosed");
    expect(inferGender("")).toBe("undisclosed");
    expect(inferGender(null)).toBe("undisclosed");
  });
});

describe("le genre affiché", () => {
  it("préfère ce que la personne a dit à ce qu'on devine", () => {
    expect(effectiveGender("undisclosed", "Clara")).toBe("undisclosed");
    expect(effectiveGender("male", "Clara")).toBe("male");
    expect(effectiveGender(null, "Clara")).toBe("female");
  });
});
