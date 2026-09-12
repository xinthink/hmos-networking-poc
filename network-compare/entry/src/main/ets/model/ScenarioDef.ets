/**
 * Shared shape of one comparison card.
 *
 * A card owns a scenario `key` (unique in the UI), the copy shown to the user,
 * and one runner per framework column. `Index.ets` renders whatever cards the
 * registries hand it; the NSC suite (`../nsc/NscSuite.ets`) contributes its own
 * group so that verification can be browsed and edited in one place.
 */
import { ScenarioResult } from './ScenarioResult';

/** One scenario mirrored across the three framework columns. */
export interface ScenarioDef {
  key: string;
  title: string;
  desc: string;
  netKit: () => Promise<ScenarioResult>;
  rcp: () => Promise<ScenarioResult>;
  axios: () => Promise<ScenarioResult>;
}

/** Which framework column a runner belongs to. */
export type ScenarioRunner = 'netkit' | 'rcp' | 'axios';

/** Callback used by self-test runners to push one result back into the UI. */
export type ScenarioSink = (key: string, runner: ScenarioRunner, text: string) => void;
