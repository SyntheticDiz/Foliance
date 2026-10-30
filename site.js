document.documentElement.classList.add("js");

const profiles = {
  overview: {
    title: "Budget proposed; delivery delayed",
    description: "The excerpt states EUR 18,000 as a proposal and says delivery is delayed. A revised date is not stated here.",
    status: "Overview · source page 4"
  },
  report: {
    title: "Cost and schedule need detail",
    description: "Check whether the EUR 18,000 budget is itemized and when delivery is expected.",
    status: "Details to verify · source page 4"
  },
  project: {
    title: "Supplier review comes first",
    description: "The revised delivery date depends on the supplier review being completed.",
    status: "Dependency · source page 4"
  },
  meeting: {
    title: "No approval or firm date recorded",
    description: "This excerpt records neither approval of the proposed budget nor a firm delivery date.",
    status: "Not recorded · source page 4"
  }
};

const tabs = [...document.querySelectorAll('[role="tab"][data-profile]')];
const panel = document.getElementById("profile-panel");
if (tabs.length && panel) {
  const title = document.getElementById("profile-title");
  const description = document.getElementById("profile-description");
  const status = document.getElementById("profile-status");

  function selectProfile(tab, moveFocus = false) {
    const profile = profiles[tab.dataset.profile];
    if (!profile) return;
    tabs.forEach(item => {
      const selected = item === tab;
      item.setAttribute("aria-selected", String(selected));
      item.tabIndex = selected ? 0 : -1;
    });
    panel.setAttribute("aria-labelledby", tab.id);
    title.textContent = profile.title;
    description.textContent = profile.description;
    status.textContent = profile.status;
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches && typeof panel.animate === "function") {
      panel.getAnimations().forEach(animation => animation.cancel());
      panel.animate([{ opacity: .25, transform: "translateY(4px)" }, { opacity: 1, transform: "translateY(0)" }],
                    { duration: 180, easing: "cubic-bezier(.2,.8,.2,1)" });
    }
    if (moveFocus) tab.focus();
  }

  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => selectProfile(tab));
    tab.addEventListener("keydown", event => {
      let nextIndex;
      if (event.key === "ArrowRight") nextIndex = (index + 1) % tabs.length;
      else if (event.key === "ArrowLeft") nextIndex = (index - 1 + tabs.length) % tabs.length;
      else if (event.key === "Home") nextIndex = 0;
      else if (event.key === "End") nextIndex = tabs.length - 1;
      else return;
      event.preventDefault();
      selectProfile(tabs[nextIndex], true);
    });
  });
}

const revealItems = document.querySelectorAll(".reveal");
if ("IntersectionObserver" in window && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.12, rootMargin: "0px 0px -24px 0px" });
  revealItems.forEach(item => observer.observe(item));
} else {
  revealItems.forEach(item => item.classList.add("is-visible"));
}
