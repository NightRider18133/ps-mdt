<script lang="ts">
    import {onMount} from "svelte";
    import {useNuiEvent} from "@/utils/useNuiEvent";
    import {setupDevelopmentMode} from "@/utils/developmentMode";
    import {createAuthService} from "../services/authService.svelte";
    import {createTabService} from "../services/tabService.svelte";
    import {settingsService} from "../services/settingsService.svelte";
    import {createInstanceStateService} from "../services/instanceStateService.svelte";
    import {NUI_EVENTS} from "@/constants/nuiEvents";
    import TopBar from "../components/TopBar.svelte";
    import NavigationPills from "../components/NavigationPills.svelte";
    import InstanceTabs from "../components/InstanceTabs.svelte";
    import ContentArea from "../components/ContentArea.svelte";
    import {prefetchCommonPages} from "@/utils/prefetch";
    import type {AuthUpdateData} from "@/interfaces/IUser";

    const authService = createAuthService();
    const tabService = createTabService();
    const instanceStateService = createInstanceStateService(tabService);

    let opacityStyle = $state("opacity: 1");

    function handleOpacityStyleChange(style: string): void {
        opacityStyle = style;
    }

    onMount(() => {
        authService.checkAuth();
        settingsService.loadColorConfig();
        setupInstanceCoordination();
        setupPrefetch();
    });

    function setupInstanceCoordination(): void {
        $effect(() => {
            const activeInstance = tabService.getActiveInstance();
            if (activeInstance) {
                instanceStateService.switchToInstance(
                    activeInstance.id,
                    activeInstance.currentTab,
                );
            }
        });
    }

    // Warm the fetchNui cache for common pages as soon as the user is
    // authenticated, so the first click on Citizens/Vehicles/etc. has
    // data ready and renders instantly.
    function setupPrefetch(): void {
        $effect(() => {
            if (authService.isAuthorized) prefetchCommonPages();
        });
    }

    useNuiEvent<AuthUpdateData>(
        NUI_EVENTS.AUTH.UPDATE_AUTH,
        (data: AuthUpdateData) => {
            authService.updateAuthState(data);
        },
    );

    setupDevelopmentMode();

    if (typeof document !== 'undefined') {
        let lastFocusedInput: HTMLElement | null = null;
        let refocusPending = false;

        document.addEventListener('focusin', (e) => {
            const el = e.target as HTMLElement;
            if (el.tagName === 'INPUT' || el.tagName === 'SELECT' || el.tagName === 'TEXTAREA' || el.isContentEditable) {
                lastFocusedInput = el;
                refocusPending = false;
            }
        });

        document.addEventListener('focusout', (e) => {
            const fe = e as FocusEvent;
            const el = e.target as HTMLElement;
            // Skip SELECT elements - their dropdown interaction triggers focusout with null relatedTarget
            if (el.tagName === 'SELECT') return;
            if (fe.relatedTarget === null && lastFocusedInput === el && !refocusPending) {
                refocusPending = true;
                requestAnimationFrame(() => {
                    if (lastFocusedInput && (!document.activeElement || document.activeElement === document.body)) {
                        lastFocusedInput.focus();
                    }
                    refocusPending = false;
                });
            }
        });

    }
</script>

<main class="mdt-container" data-job-type={authService.jobType}>
    <div class="mdt-window" style={opacityStyle}>
        <div class="mdt-interface">
            <TopBar
                    {authService}
                    onOpacityStyleChange={handleOpacityStyleChange}
            />

            <div class="mdt-content">
                {#if !authService.isCivilian}
                    <div class="mdt-navigation">
                        {#if authService.isAuthorized}
                            <NavigationPills {tabService} jobType={authService.jobType} {authService}/>
                        {/if}
                    </div>
                {/if}
                <div class="mdt-main-content">
                    {#if !authService.isCivilian}
                        <InstanceTabs {tabService}/>
                    {/if}
                    <ContentArea
                            {authService}
                            {tabService}
                            {instanceStateService}
                    />
                </div>
            </div>
        </div>
    </div>
</main>

<style>
    /* Outer scrim — kept transparent so the game world stays visible around
       the tablet shell, matching how NR_Tablet sits over the wallpaper. */
    .mdt-container {
        position: fixed;
        inset: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 1000;
        background: transparent;
    }

    /* Tablet bezel — sized to feel like a real tablet rather than fill the
       screen. min(80vw, 1500px) keeps it tight on ultrawides; aspect-ish
       height around 80vh. 1 unit (--u) = 1px @ 1080p.

       The bezel uses a transparent border + dual background-image trick to
       paint a brushed-aluminium gradient on the border itself: the inner
       layer (padding-box) is the dark content background; the outer layer
       (border-box) is the metallic bezel gradient. */
    .mdt-window {
        width: min(80vw, 1500px);
        height: min(82vh, 920px);
        background: linear-gradient(180deg, rgba(13, 18, 32, 0.96), rgba(7, 10, 20, 0.98));
        border-radius: calc(var(--u, 0.092592592vh) * 15);
        overflow: hidden;
        display: flex;
        flex-direction: column;
        position: relative;
        transition: opacity 0.2s ease-in-out;
        will-change: opacity;
        border: calc(var(--u, 0.092592592vh) * 3) solid #3a3d44;
        box-shadow:
            0 calc(var(--u, 0.092592592vh) * 30) calc(var(--u, 0.092592592vh) * 60) rgba(0, 0, 0, 0.55),
            /* hairline highlight along the very top of the bezel — simulates
               light catching the metal edge */
            inset 0 1px 0 rgba(255, 255, 255, 0.18),
            /* outer 1px ring giving the bezel some separation from the scrim */
            0 0 0 1px rgba(0, 0, 0, 0.4);
    }

    /* Top-down accent glow only — the dark navy gradient on .mdt-window does
       all the heavy lifting for the background. No grid overlay. */
    .mdt-window::before {
        content: "";
        position: absolute;
        inset: 0;
        pointer-events: none;
        background: radial-gradient(
            120% 60% at 50% 0%,
            rgba(31, 116, 227, 0.10) 0%,
            rgba(31, 116, 227, 0) 60%
        );
        z-index: 0;
    }

    /* EMS and DOJ use the same neutral chrome as LEO. Their accent colours
       still come through on pills, buttons, active nav state, and the dark
       gradient EMS palette in app.css — but we don't tint the bezel or
       inner glow, which read as "weird red glow" / "weird gold glow"
       around the whole window. Keep things neutral. */

    .mdt-interface {
        width: 100%;
        height: 100%;
        display: flex;
        flex-direction: column;
        position: relative;
        z-index: 1;
    }

    .mdt-content {
        display: flex;
        height: calc(100% - 55px); /* Adjust for TopBar height */
    }

    /* Navigation column — translucent glass over the deep navy backdrop,
       mirroring NR_Tablet's app dock styling. */
    .mdt-navigation {
        max-width: 250px;
        background: var(--glass-bg-strong, var(--card-dark-bg));
        backdrop-filter: blur(calc(var(--u, 0.092592592vh) * 15));
        -webkit-backdrop-filter: blur(calc(var(--u, 0.092592592vh) * 15));
        border-right: 1px solid var(--glass-border, rgba(255, 255, 255, 0.08));
        display: flex;
    }

    .mdt-main-content {
        display: flex;
        flex-direction: column;
        flex: 1;
        min-width: 0;
        width: 100%;
    }
</style>